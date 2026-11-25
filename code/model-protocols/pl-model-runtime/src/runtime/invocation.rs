//! Invocation admission, cancellation and final observation handoff.
mod attempt;
mod connection;
mod prepare;
mod recovery;
mod timing;
pub(crate) use recovery::InvocationReport;

use super::{ModelInvocationContext, ModelRuntime};
use crate::completion::{CompletionFailure, CompletionRequest, CompletionResponse};
use crate::stream::CompletionEventStream;
use pl_protocol::PureError;
use std::sync::atomic::{AtomicU8, Ordering};
use std::time::Duration;

#[repr(u8)]
enum DispatchStage {
    Unsent,
    Connecting,
    Submitted,
}

// The opening future can be dropped by cancellation. Keep the last actual transport boundary
// outside that future so cancellation and opening errors retain the same evidence.
pub(super) struct AttemptDispatch<'a> {
    stage: AtomicU8,
    progress: Option<&'a pl_core::model::ModelProgressSender>,
}

impl<'a> AttemptDispatch<'a> {
    fn new(progress: Option<&'a pl_core::model::ModelProgressSender>) -> Self {
        Self {
            stage: AtomicU8::new(DispatchStage::Unsent as u8),
            progress,
        }
    }

    fn mark(&self, stage: DispatchStage) {
        let previous = self.stage.swap(stage as u8, Ordering::Relaxed);
        if previous == DispatchStage::Unsent as u8
            && let Some(progress) = self.progress
        {
            progress.start_recovery_send();
        }
    }

    pub(super) fn connecting(&self) {
        self.mark(DispatchStage::Connecting);
    }
    pub(super) fn submitting(&self) {
        self.mark(DispatchStage::Submitted);
    }

    fn started(&self) -> bool {
        self.stage.load(Ordering::Relaxed) != DispatchStage::Unsent as u8
    }

    fn submitted(&self) -> bool {
        self.stage.load(Ordering::Relaxed) == DispatchStage::Submitted as u8
    }
}

struct OpenedCompletionStream {
    events: CompletionEventStream,
    sent_model: String,
    idle_timeout: Option<Duration>,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum OpenAiTransport {
    ResponsesWebSocket,
    Http,
}

impl OpenAiTransport {
    fn trace_label(self) -> &'static str {
        match self {
            Self::ResponsesWebSocket => "ws",
            Self::Http => "http",
        }
    }
}

impl std::fmt::Debug for ModelRuntime {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ModelRuntime")
            .field("account", &self.account_id)
            .field("model", &self.model.base.slug)
            .field("transport", &self.model.extra.binding.transport)
            .field("pricing_mode", &self.pricing_mode)
            .finish_non_exhaustive()
    }
}

impl ModelRuntime {
    pub(super) fn resolve_base_url(&self) -> String {
        self.endpoint.base_url.trim_end_matches('/').to_owned()
    }

    /// Executes a canonical request with session admission, bounded recovery and final accounting.
    ///
    /// # Errors
    /// Returns a typed failure retaining accepted output, usage and cancellation facts.
    pub async fn complete(
        &self,
        request: CompletionRequest,
        context: ModelInvocationContext,
    ) -> std::result::Result<CompletionResponse, CompletionFailure> {
        self.complete_with_report(request, context, &mut InvocationReport::default())
            .await
    }

    pub(super) async fn complete_with_report(
        &self,
        request: CompletionRequest,
        mut context: ModelInvocationContext,
        report: &mut InvocationReport,
    ) -> std::result::Result<CompletionResponse, CompletionFailure> {
        use super::invocation_context::BoundSettlement;
        let settlement = context.settlement.take().ok_or_else(|| {
            CompletionFailure::from(PureError::Io(std::io::Error::other(
                pl_core::model::ModelMemberError::SettlementUnavailable,
            )))
        })?;
        if let BoundSettlement::Thread(port) = &settlement
            && !context.trace.as_ref().is_some_and(|trace| {
                trace.session_id == port.thread_id()
                    && trace.turn_id == port.turn_id().unwrap_or_else(|| port.attempt_id())
                    && trace.inference_id == port.attempt_id()
            })
        {
            return Err(PureError::Protocol(
                "model invocation identity does not match its settlement port".into(),
            )
            .into());
        }
        let owner_closing = settlement.cancellation().cloned();
        let progress = context
            .progress
            .get_or_insert_with(|| {
                pl_core::model::ModelProgressSender::detached(
                    crate::stream::MAX_COMPLETION_OUTPUT_BYTES as u64,
                )
            })
            .clone();
        // A Thread-owned channel is initialized with its stable turn/attempt live marker. Do not
        // replace it with a default snapshot here: doing so would erase the identity before the
        // first provider event and make a reused invocation look like an unowned observation.
        let caller_cancellation = context.cancellation.take().unwrap_or_default();
        let closing = context.session.closing_token();
        // Propagate caller cancellation synchronously, including when it happens inside an
        // invocation poll (for example while charging a member before sending it). Waiting for
        // the outer select to be polled again would let that same poll send after cancellation.
        // Session close may cancel this child without cancelling the caller's parent token.
        let cancellation = caller_cancellation.child_token();
        context.cancellation = Some(cancellation.clone());
        let current_link = context.current.clone();
        let mut current = current_link.as_ref().and_then(|link| link.take_producer());
        if current_link.is_some() && current.is_none() {
            return Err(CompletionFailure::new(
                PureError::Protocol("current invocation endpoint was already consumed".into()),
                Box::default(),
            ));
        }
        let mut result = {
            let invocation =
                self.complete_inner(request, context, &settlement, current.as_mut(), report);
            tokio::pin!(invocation);
            // Cancellation is cooperative: await the same invocation so its partial
            // accounting and transport guards finish before releasing admission.
            tokio::select! {
                biased;
                _ = async {
                    match &owner_closing {
                        Some(token) => tokio::select! { _ = token.cancelled() => (), _ = closing.cancelled() => () },
                        None => closing.cancelled().await,
                    }
                } => {
                    cancellation.cancel();
                    invocation.await
                }
                result = &mut invocation => result,
            }
        };
        if let Some(current) = current.as_mut() {
            match current.finish(result.as_ref().err().map(ToString::to_string)) {
                Ok(payload) => current_link
                    .as_ref()
                    .expect("current invocation")
                    .handoff(payload),
                Err(error) if result.is_ok() => {
                    let response = result.as_ref().expect("successful result");
                    let mut failure = CompletionFailure::new(
                        PureError::Protocol(error.to_string()),
                        Box::new(response.accounting.clone()),
                    );
                    failure.usage_is_terminal = response.usage_is_terminal;
                    result = Err(failure);
                }
                Err(_) => {} // Core rejects an exit without a complete final current payload.
            }
        }
        match &mut result {
            Ok(response) => {
                progress.finish_recovery(pl_core::model::ModelRecoveryPhase::Recovered);
                response.observation = progress.latest().observation().clone();
                response.settlements = std::mem::take(&mut report.settlements);
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
                error.settlements = std::mem::take(&mut report.settlements);
            }
        }
        result
    }
}

#[cfg(test)]
mod cache_tests {
    use super::*;
    use crate::model::ModelDefinition;
    use crate::model::{ModelParameter, ModelTransportProfile, ParameterWire, WireAssignment};
    use crate::protocol::PromptCacheDialect;

    use crate::runtime::invocation_context::InvocationPurpose;
    use serde_json::json;

    fn runner(enabled: bool) -> ModelRuntime {
        let mut endpoint =
            pl_model_openai::endpoint::compatible_endpoint("cache", "http://127.0.0.1:1");
        if enabled {
            endpoint.service_capabilities.prompt_cache.dialect = PromptCacheDialect::ExplicitKey;
        }
        let mut model = ModelDefinition::compatible("cache-model");
        model
            .extra
            .binding
            .set_transport(ModelTransportProfile::responses_http());
        ModelRuntime::bind(
            "cache-account",
            endpoint,
            model,
            &pl_model_openai_wire::OPENAI_WIRE_CODEC,
            pl_model_openai::adapter::COMPATIBLE_ADAPTER.error_policy,
            None,
        )
        .unwrap()
    }

    #[test]
    fn cache_policy_applies_at_request_preparation() {
        let (prepared, _) = runner(false)
            .prepare_request_body(
                CompletionRequest::builder().build(),
                Some("caller-key"),
                &InvocationPurpose::Completion,
            )
            .unwrap();
        assert!(
            serde_json::Value::Object(prepared.body)
                .get("prompt_cache_key")
                .is_none()
        );
    }

    #[test]
    fn cache_key_overrides_are_rejected_before_io() {
        for expected in [None, Some("thread-key")] {
            for value in [json!("shared-key"), json!(null)] {
                let mut fixed = runner(true);
                fixed
                    .model
                    .extra
                    .binding
                    .request
                    .body
                    .insert("prompt_cache_key".into(), value.clone());
                assert!(
                    fixed
                        .prepare_request_body(
                            CompletionRequest::builder().build(),
                            expected,
                            &InvocationPurpose::Completion
                        )
                        .is_err(),
                    "fixed body: {value}"
                );

                let mut parameter = runner(true);
                parameter.model.set_parameters(vec![ModelParameter {
                    candidate_display_names: Default::default(),
                    name: "effort".into(),
                    label: None,
                    default: None,
                    candidates: vec!["low".into()],
                    wire: std::collections::BTreeMap::from([(
                        "low".into(),
                        ParameterWire {
                            set: vec![WireAssignment {
                                path: "prompt_cache_key".into(),
                                value,
                            }],
                            remove: vec![],
                        },
                    )]),
                }]);
                let request = CompletionRequest::builder()
                    .reasoning(Some(crate::completion::ReasoningConfig {
                        effort: Some("low".into()),
                        summary: None,
                    }))
                    .build();
                assert!(
                    parameter
                        .prepare_request_body(request, expected, &InvocationPurpose::Completion)
                        .is_err(),
                    "parameter wire"
                );
            }
        }
        let mut removed = runner(true);
        removed.model.set_parameters(vec![ModelParameter {
            candidate_display_names: Default::default(),
            name: "effort".into(),
            label: None,
            default: None,
            candidates: vec!["low".into()],
            wire: std::collections::BTreeMap::from([(
                "low".into(),
                ParameterWire {
                    set: vec![],
                    remove: vec!["prompt_cache_key".into()],
                },
            )]),
        }]);
        let request = CompletionRequest::builder()
            .reasoning(Some(crate::completion::ReasoningConfig {
                effort: Some("low".into()),
                summary: None,
            }))
            .build();
        assert!(
            removed
                .prepare_request_body(request, Some("thread-key"), &InvocationPurpose::Completion)
                .is_err()
        );
    }
}

#[cfg(test)]
pub(in crate::runtime) mod chatgpt_tests {
    use super::*;
    use crate::completion::{Message, MessageContent, MessageRole, ToolCallKind};
    use crate::completion::{SystemPrompt, ToolSpec};

    use crate::runtime::invocation_context::InvocationPurpose;
    use pl_model_auth::chatgpt::{
        ChatGptAuthError, ChatGptCredentialRecord, ChatGptCredentialStorage, ChatGptSession,
    };
    use serde_json::json;
    use std::sync::Arc;

    struct NoCredentialIo;
    impl ChatGptCredentialStorage for NoCredentialIo {
        fn load(&self) -> std::result::Result<ChatGptCredentialRecord, ChatGptAuthError> {
            panic!("wire preparation must not read credentials")
        }
        fn persist(
            &self,
            _: &str,
            _: &ChatGptCredentialRecord,
        ) -> std::result::Result<(), ChatGptAuthError> {
            panic!("wire preparation must not write credentials")
        }
    }

    fn fixture() -> (tempfile::TempDir, ModelRuntime) {
        fixture_for(false)
    }

    pub(in crate::runtime) fn fixture_for(codex: bool) -> (tempfile::TempDir, ModelRuntime) {
        let temp = tempfile::tempdir().unwrap();
        let record = ChatGptCredentialRecord {
            schema_version: 1,
            registration_id: "wire-registration".into(),
            account: pl_model_auth::chatgpt::ChatGptAccountInfo {
                issuer: "https://auth.openai.com".into(),
                subject: "wire-subject".into(),
                client_id: if codex {
                    pl_model_auth::chatgpt::CODEX_CLIENT_ID
                } else {
                    "issued-wire-client"
                }
                .into(),
                email: None,
                plan_usage_enabled: true,
                codex: codex.then(|| pl_model_auth::chatgpt::CodexAccountInfo {
                    account_id: "selected-workspace".into(),
                    plan_type: None,
                }),
            },
            ext_agent_host_id: "urn:uuid:00000000-0000-4000-8000-000000000001".into(),
            access_token: "synthetic-access".into(),
            refresh_token: "synthetic-refresh".into(),
            id_token: "synthetic-id".into(),
            scopes: vec!["chatgpt.tokens.use.direct".into()],
            expires_at: i64::MAX,
            earliest_refresh_at: None,
            refresh_in_flight: false,
        };
        let mut endpoint = pl_model_openai::endpoint::endpoint(None);
        endpoint.authorization = Some(pl_model_wire::authorization::EndpointAuthorization::new(
            ChatGptSession::new(
                &record,
                Arc::new(NoCredentialIo),
                temp.path().join("must-not-lock"),
            )
            .unwrap(),
        ));
        let mut info = crate::model::ModelDefinition::compatible("fixture-model");
        info.extra.binding.transport = crate::model::ModelTransportProfile::responses_http();
        info.extra.binding.request = crate::model::ModelRequestProfile::responses();
        info.extra.capabilities.tools.function_calling = true;
        info.extra.capabilities.tools.custom_tools = true;
        info.extra.capabilities.tools.freeform_tools = true;
        info.extra.capabilities.reasoning = true;
        (
            temp,
            ModelRuntime::bind(
                "wire",
                endpoint,
                info,
                &pl_model_openai_wire::OPENAI_WIRE_CODEC,
                pl_model_openai::adapter::COMPATIBLE_ADAPTER.error_policy,
                None,
            )
            .unwrap(),
        )
    }

    fn message(role: MessageRole, text: &str) -> Message {
        Message {
            role,
            content: MessageContent::text(text),
            presentation: Default::default(),
            reasoning_content: None,
            tool_calls: None,
            tool_result: None,
            metadata: Default::default(),
        }
    }

    pub(in crate::runtime) fn catalog(
        entry: serde_json::Value,
        previous: Option<&[crate::model::ModelDefinition]>,
    ) -> Vec<crate::model::ModelDefinition> {
        let records = pl_model_wire::generic_catalog::openai_records(
            &serde_json::to_vec(&json!({"models":[entry]})).unwrap(),
        )
        .unwrap();
        pl_model_wire::discovery::models(
            records,
            &crate::config::ModelCatalogDiscovery {
                transport: crate::model::ModelTransportProfile::responses_http(),
            },
            pl_model_openai::adapter::CATALOG,
            previous,
            &[],
        )
        .unwrap()
    }

    #[test]
    fn codex_service_tiers_catalog_presence_names_and_defaults() {
        for (tiers, default, candidates, names, expected_default) in [
            (
                json!([{"id":"priority","name":"Fast","description":{"ignored":true},"wire":{"set":[{"path":"model","value":"must-not-apply"}]}}, {"id":"ultrafast","name":"Ultrafast"}]),
                "ultrafast",
                vec!["priority", "ultrafast"],
                vec![("priority", "Fast"), ("ultrafast", "Ultrafast")],
                Some("ultrafast"),
            ),
            (
                json!([{"id":"ultrafast"}]),
                "priority",
                vec!["ultrafast"],
                vec![],
                None,
            ),
            (
                json!([{"id":"priority","name":"  "}]),
                "priority",
                vec!["priority"],
                vec![],
                Some("priority"),
            ),
            (
                json!([{"id":"priority","name":" Fast "}]),
                "priority",
                vec!["priority"],
                vec![("priority", " Fast ")],
                Some("priority"),
            ),
            (
                json!([{"id":" priority ","name":"Fast"}]),
                " priority ",
                vec![" priority "],
                vec![(" priority ", "Fast")],
                Some(" priority "),
            ),
            (json!([]), "priority", vec![], vec![], None),
        ] {
            let models = catalog(
                json!({"slug":"fixture-model","service_tiers":tiers,"default_service_tier":default}),
                None,
            );
            let tier = models[0]
                .extra
                .parameters
                .iter()
                .find(|p| p.name == "service_tier");
            if candidates.is_empty() {
                assert!(tier.is_none());
                continue;
            }
            let tier = tier.unwrap();
            assert_eq!(tier.candidates, candidates);
            assert_eq!(tier.default.as_deref(), expected_default);
            assert_eq!(
                tier.candidate_display_names,
                names
                    .into_iter()
                    .map(|(id, name)| (id.into(), name.into()))
                    .collect()
            );
            for id in &tier.candidates {
                assert_eq!(
                    tier.wire[id].set,
                    vec![crate::model::WireAssignment {
                        path: "service_tier".into(),
                        value: json!(id)
                    }]
                );
            }
        }
        let missing = catalog(
            json!({"slug":"fixture-model","additional_speed_tiers":["priority"]}),
            None,
        );
        assert!(
            missing[0]
                .extra
                .parameters
                .iter()
                .all(|p| p.name != "service_tier")
        );
    }

    #[test]
    fn codex_service_tiers_are_independent_from_reasoning_and_withdraw_explicitly() {
        let initial = catalog(
            json!({"slug":"fixture-model","service_tiers":[{"id":"priority"}],"default_service_tier":"priority","supported_reasoning_levels":[{"effort":"high"}]}),
            None,
        );
        let reasoning = catalog(
            json!({"slug":"fixture-model","parameters":[{"name":"effort","candidates":["low"],"wire":{"low":{"set":[{"path":"reasoning.effort","value":"low"}]}}}]}),
            Some(&initial),
        );
        assert_eq!(reasoning[0].supported_efforts(), ["low"]);
        assert!(
            reasoning[0]
                .extra
                .parameters
                .iter()
                .any(|p| p.name == "service_tier")
        );
        let default_cleared = catalog(
            json!({"slug":"fixture-model","default_service_tier":null}),
            Some(&reasoning),
        );
        let tier = default_cleared[0]
            .extra
            .parameters
            .iter()
            .find(|p| p.name == "service_tier")
            .unwrap();
        assert_eq!(tier.candidates, ["priority"]);
        assert_eq!(tier.default, None);
        let cleared = catalog(
            json!({"slug":"fixture-model","service_tiers":[]}),
            Some(&reasoning),
        );
        assert_eq!(cleared[0].supported_efforts(), ["low"]);
        assert!(
            cleared[0]
                .extra
                .parameters
                .iter()
                .all(|p| p.name != "service_tier")
        );
        let mut merged = initial[0].clone();
        let mut reasoning_only = reasoning[0].clone();
        reasoning_only
            .extra
            .parameters
            .retain(|p| p.name == "effort");
        crate::model::observation::apply_field(
            &mut merged,
            &reasoning_only,
            crate::model::ModelMetadataField::Parameters,
        );
        assert!(
            merged
                .extra
                .parameters
                .iter()
                .any(|p| p.name == "service_tier")
        );
        crate::model::observation::apply_field(
            &mut merged,
            &cleared[0],
            crate::model::ModelMetadataField::ServiceTiers,
        );
        assert_eq!(merged.supported_efforts(), ["low"]);
        assert!(
            merged
                .extra
                .parameters
                .iter()
                .all(|p| p.name != "service_tier")
        );
    }

    #[test]
    fn service_tier_request_is_exact_optional_and_validated_before_io() {
        let (_temp, mut runner) = fixture_for(true);
        runner.model = catalog(json!({"slug":"fixture-model","service_tiers":[{"id":"priority"},{"id":"ultrafast"},{"id":"custom-tier"}],"default_service_tier":"ultrafast","supported_reasoning_levels":[{"effort":"high"}]}), None).remove(0);
        assert!(body(&runner, request()).get("service_tier").is_none());
        for tier in ["priority", "ultrafast", "custom-tier"] {
            let mut request = request();
            request.service_tier = Some(tier.into());
            request.reasoning = Some(crate::completion::ReasoningConfig {
                effort: Some("high".into()),
                summary: None,
            });
            let body = body(&runner, request);
            assert_eq!(body["service_tier"], tier);
            assert_eq!(body["reasoning"]["effort"], "high");
        }
        for tier in ["", "standard", "auto", "Priority", " priority"] {
            let mut request = request();
            request.service_tier = Some(tier.into());
            assert!(matches!(
                runner.prepare_request_body(request, None, &InvocationPurpose::Completion),
                Err(PureError::ConfigError(_))
            ));
        }
        let mut selected = request();
        selected.service_tier = Some("priority".into());
        assert!(matches!(
            runner.prepare_request_body(
                selected,
                None,
                &InvocationPurpose::RemoteCompaction {
                    headers: Default::default(),
                    body: Default::default(),
                }
            ),
            Err(PureError::ConfigError(_))
        ));
        let mut selected = request();
        selected.service_tier = Some("priority".into());
        let summary = crate::completion::summary_request("summarize", selected, "keep facts", None);
        assert!(body(&runner, summary).get("service_tier").is_none());
        runner
            .model
            .extra
            .binding
            .request
            .body
            .insert("service_tier".into(), json!("explicit-raw"));
        assert_eq!(body(&runner, request())["service_tier"], "explicit-raw");
        let mut forged = runner.clone();
        let tier = forged
            .model
            .extra
            .parameters
            .iter_mut()
            .find(|p| p.name == "service_tier")
            .unwrap();
        tier.wire.get_mut("priority").unwrap().set[0].path = "model".into();
        let mut selected = request();
        selected.service_tier = Some("priority".into());
        assert!(matches!(
            forged.prepare_request(selected),
            Err(PureError::ConfigError(_))
        ));
    }
    fn request() -> CompletionRequest {
        CompletionRequest::builder()
            .system_prompt(SystemPrompt::new("trusted"))
            .messages(vec![message(MessageRole::User, "task")])
            .build()
    }
    fn body(runner: &ModelRuntime, request: CompletionRequest) -> serde_json::Value {
        serde_json::Value::Object(
            runner
                .prepare_request_body(request, None, &InvocationPurpose::Completion)
                .unwrap()
                .0
                .body,
        )
    }

    #[test]
    fn siwc_tools_keep_sorted_declarations_and_match_history_results() {
        let (_temp, runner) = fixture();
        let mut request = request();
        let schema = json!({"type":"object","properties":{"q":{"type":"string"}},"required":["q"],"additionalProperties":false});
        request.tools = vec![
            crate::completion::tool_definition_to_spec(
                &pl_agent_tool::ToolDefinition::json("lookup", "lookup", schema).unwrap(),
                crate::completion::ToolCallPolicy::DirectOnly,
            ),
            crate::completion::tool_definition_to_spec(
                &pl_agent_tool::ToolDefinition::grammar("edit", "edit", "lark", "start: WORD")
                    .unwrap(),
                crate::completion::ToolCallPolicy::DirectOnly,
            ),
        ];
        let mut assistant = message(MessageRole::Assistant, "");
        assistant.tool_calls = Some(vec![crate::completion::ToolCallRecord {
            item_id: "item-edit".into(),
            call_id: "call-edit".into(),
            name: "edit".into(),
            kind: ToolCallKind::Custom,
            arguments: json!("payload"),
            caller: None,
        }]);
        assistant
            .tool_calls
            .as_mut()
            .unwrap()
            .push(crate::completion::ToolCallRecord {
                item_id: "item-lookup".into(),
                call_id: "call-lookup".into(),
                name: "lookup".into(),
                kind: ToolCallKind::Function,
                arguments: json!({"q":"task"}),
                caller: None,
            });
        let mut output = message(MessageRole::Tool, "edited");
        output.tool_result = Some(crate::completion::ToolResultRecord {
            item_id: "item-edit".into(),
            call_id: "call-edit".into(),
            name: "edit".into(),
            kind: ToolCallKind::Custom,
        });
        let mut function_output = message(MessageRole::Tool, "found");
        function_output.tool_result = Some(crate::completion::ToolResultRecord {
            item_id: "item-lookup".into(),
            call_id: "call-lookup".into(),
            name: "lookup".into(),
            kind: ToolCallKind::Function,
        });
        request
            .input
            .extend([assistant.into(), output.into(), function_output.into()]);
        let encoded = body(&runner, request);
        assert!(encoded.get("tools").is_none());
        let declarations = &encoded["input"][1];
        // Retain the existing canonical tool-schema ordering, not a new SIWC registry.
        assert_eq!(declarations["tools"][1]["name"], "lookup");
        assert_eq!(declarations["tools"][0]["name"], "edit");

        assert_eq!(encoded["input"][3]["call_id"], "call-edit");
        assert_eq!(encoded["input"][4]["call_id"], "call-lookup");
        assert_eq!(encoded["input"][5]["call_id"], "call-edit");
        assert_eq!(encoded["input"][5]["output"], "edited");
        assert_eq!(encoded["input"][6]["call_id"], "call-lookup");
        assert_eq!(encoded["input"][6]["output"], "found");
        assert!(
            body(
                &runner,
                CompletionRequest::builder()
                    .messages(vec![message(MessageRole::User, "task")])
                    .build()
            )["input"]
                .as_array()
                .unwrap()
                .iter()
                .all(|item| item["type"] != "additional_tools")
        );
    }

    #[test]
    fn siwc_rejects_explicit_parameters_and_all_override_sources_before_io() {
        let (_temp, runner) = fixture();
        let mut temperature = request();
        temperature.temperature = Some(0.1);
        let mut limit = request();
        limit.max_tokens = Some(10);
        for request in [temperature, limit] {
            assert!(
                runner
                    .prepare_request_body(request, None, &InvocationPurpose::Completion)
                    .is_err()
            );
        }
        let mut overrides = vec![
            json!({"store":true}),
            json!({"stream":false}),
            json!({"input":"not-array"}),
            json!({"input":[]}),
            json!({"tools":[{"type":"tool_search"}]}),
            json!({"instructions":"secret-value"}),
        ];
        for field in [
            "background",
            "conversation",
            "max_output_tokens",
            "max_tool_calls",
            "metadata",
            "moderation",
            "multi_agent",
            "prompt",
            "prompt_cache_retention",
            "safety_identifier",
            "temperature",
            "top_logprobs",
            "top_p",
            "truncation",
            "user",
            "previous_response_id",
        ] {
            overrides.push(json!({field:null}));
        }
        for value in overrides {
            let overlay = value.as_object().unwrap().clone();
            let mut fixed = runner.clone();
            fixed.model.extra.binding.request.body = overlay.clone();
            assert!(
                fixed
                    .prepare_request_body(request(), None, &InvocationPurpose::Completion)
                    .is_err(),
                "{value}"
            );
            let mut parameter = runner.clone();
            let wire = crate::model::ParameterWire {
                set: overlay
                    .into_iter()
                    .map(|(path, value)| crate::model::WireAssignment { path, value })
                    .collect(),
                remove: vec![],
            };
            parameter
                .model
                .set_parameters(vec![crate::model::ModelParameter {
                    candidate_display_names: Default::default(),
                    name: "effort".into(),
                    label: None,
                    default: Some("low".into()),
                    candidates: vec!["low".into()],
                    wire: std::collections::BTreeMap::from([("low".into(), wire)]),
                }]);
            let mut selected = request();
            selected.reasoning = Some(crate::completion::ReasoningConfig {
                effort: Some("low".into()),
                summary: None,
            });
            assert!(
                parameter
                    .prepare_request_body(selected, None, &InvocationPurpose::Completion)
                    .is_err(),
                "{value}"
            );
        }
        let mut supported = runner.clone();
        supported
            .model
            .set_parameters(vec![crate::model::ModelParameter {
                candidate_display_names: Default::default(),
                name: "effort".into(),
                label: None,
                default: Some("low".into()),
                candidates: vec!["low".into()],
                wire: std::collections::BTreeMap::from([(
                    "low".into(),
                    crate::model::ParameterWire {
                        set: vec![
                            crate::model::WireAssignment {
                                path: "reasoning.effort".into(),
                                value: json!("low"),
                            },
                            crate::model::WireAssignment {
                                path: "store".into(),
                                value: json!(false),
                            },
                            crate::model::WireAssignment {
                                path: "stream".into(),
                                value: json!(true),
                            },
                        ],
                        remove: vec![],
                    },
                )]),
            }]);
        let mut selected = request();
        selected.reasoning = Some(crate::completion::ReasoningConfig {
            effort: Some("low".into()),
            summary: None,
        });
        assert_eq!(body(&supported, selected)["reasoning"]["effort"], "low");
    }

    #[test]
    fn siwc_rejects_unsupported_tools_without_downgrading_callers_or_native_history() {
        let (_temp, runner) = fixture();
        let mut unsupported_custom = runner.clone();
        unsupported_custom
            .model
            .extra
            .capabilities
            .tools
            .custom_tools = false;
        unsupported_custom
            .model
            .extra
            .capabilities
            .tools
            .freeform_tools = false;
        let mut selected = request();
        selected.tools = vec![crate::completion::tool_definition_to_spec(
            &pl_agent_tool::ToolDefinition::grammar("edit", "edit", "lark", "start: WORD").unwrap(),
            crate::completion::ToolCallPolicy::DirectOnly,
        )];
        assert!(
            unsupported_custom
                .prepare_request_body(selected, None, &InvocationPurpose::Completion)
                .is_err()
        );
        let mut search_request = request();
        search_request.tools = vec![ToolSpec::WebSearch {
            options: crate::completion::HostedWebSearchOptions::OpenAi {
                external_web_access: false,
                indexed_web_access: None,
                filters: None,
                user_location: None,
                search_context_size: None,
                search_content_types: None,
            },
        }];
        let mut search = runner.clone();
        search.model.extra.capabilities.web_search = true;
        search
            .endpoint
            .service_capabilities
            .web_search
            .hosted_responses = true;
        assert_eq!(
            body(&search, search_request.clone())["tools"][0]["type"],
            "web_search"
        );
        search
            .endpoint
            .service_capabilities
            .web_search
            .hosted_responses = false;
        assert!(
            search
                .prepare_request_body(search_request, None, &InvocationPurpose::Completion)
                .is_err()
        );
        let mut function_patch = request();
        function_patch.tools = vec![crate::completion::tool_definition_to_spec(
            &pl_agent_tool::ToolDefinition::json("apply_patch", "frozen", json!({"type":"object"}))
                .unwrap(),
            crate::completion::ToolCallPolicy::DirectOnly,
        )];
        let encoded = body(&runner, function_patch);
        assert_eq!(encoded["input"][1]["tools"][0]["type"], "function");
        assert_eq!(
            encoded["input"][1]["tools"][0]["parameters"],
            json!({"type":"object"})
        );
        let mut only_programmatic = crate::completion::tool_definition_to_spec(
            &pl_agent_tool::ToolDefinition::json("p", "p", json!({"type":"object"})).unwrap(),
            crate::completion::ToolCallPolicy::DirectOnly,
        );
        if let ToolSpec::Function {
            allowed_callers, ..
        } = &mut only_programmatic
        {
            *allowed_callers = vec![crate::completion::ToolCallerMode::Programmatic];
        }
        for tool in [ToolSpec::ProgrammaticToolCalling, only_programmatic] {
            let mut selected = request();
            selected.tools = vec![tool];
            assert!(
                runner
                    .prepare_request_body(selected, None, &InvocationPurpose::Completion)
                    .is_err()
            );
        }
        let mut mixed = crate::completion::tool_definition_to_spec(
            &pl_agent_tool::ToolDefinition::json("mixed", "mixed", json!({"type":"object"}))
                .unwrap(),
            crate::completion::ToolCallPolicy::DirectOnly,
        );
        if let ToolSpec::Function {
            allowed_callers, ..
        } = &mut mixed
        {
            *allowed_callers = vec![
                crate::completion::ToolCallerMode::Direct,
                crate::completion::ToolCallerMode::Programmatic,
            ];
        }
        let mut selected = request();
        selected.tools = vec![mixed];
        assert_eq!(
            body(&runner, selected)["input"][1]["tools"][0]["allowed_callers"],
            json!(["direct", "programmatic"])
        );
        for value in [
            json!({"type":"program","id":"p"}),
            json!({"type":"tool_search_call","id":"s"}),
            json!({"type":"message","role":"system","content":[]}),
            json!({"type":"additional_tools","role":"developer","tools":[]}),
        ] {
            let mut selected = request();
            // Test the opaque input path without introducing a second codec or network bypass.
            selected.input.push(
                crate::completion::ResponsesContextItem {
                    kind: crate::completion::ResponsesContextItemKind::Unknown,
                    value,
                }
                .into(),
            );
            assert!(
                runner
                    .prepare_request_body(selected, None, &InvocationPurpose::Completion)
                    .is_err()
            );
        }
        let mut selected = request();
        let reasoning =
            json!({"type":"reasoning","id":"r","encrypted_content":"opaque","status":"completed"});
        selected.input.push(
            crate::completion::ResponsesContextItem {
                kind: crate::completion::ResponsesContextItemKind::Reasoning,
                value: reasoning.clone(),
            }
            .into(),
        );
        assert_eq!(body(&runner, selected)["input"][2], reasoning);
    }

    #[tokio::test]
    async fn siwc_thread_keeps_capacity_metadata_but_does_not_invent_an_output_limit() {
        use pl_core::{
            context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource},
            model::{Model, ModelRequest, ToolCallMode},
        };
        let (_temp, mut runner) = fixture();
        runner.model.extra.max_output_tokens = Some(4096);
        if let crate::model::ModelProtocolOptions::Responses(options) =
            &mut runner.model.extra.binding.request.protocol
        {
            options.max_tokens_field = crate::model::ResponsesMaxTokensField::MaxOutputTokens;
        }
        let runtime = crate::runtime::ModelRuntime::bind(
            "wire",
            runner.endpoint.clone(),
            runner.model.clone(),
            &pl_model_openai_wire::OPENAI_WIRE_CODEC,
            pl_model_openai::adapter::COMPATIBLE_ADAPTER.error_policy,
            None,
        )
        .unwrap();
        assert_eq!(runtime.model().extra.max_output_tokens, Some(4096));
        let model = crate::runtime::ThreadModel::new(runtime, None);
        let mut session = model.open_session().await.unwrap();
        let prepared = session
            .prepare(ModelRequest {
                thread_id: "t".into(),
                turn_id: "turn".into(),
                attempt_id: "a".into(),
                context: ContextSnapshot {
                    revision: 1,
                    records: vec![ContextRecord {
                        id: "u".into(),
                        turn_id: None,
                        source: ContextSource::User,
                        content: vec![ContextContent::Text {
                            text: "task".into(),
                        }],
                        tool_calls: vec![],
                    }]
                    .into(),
                },
                tools: vec![].into(),
                tool_call_mode: ToolCallMode::Parallel,
                solo_tool_ids: Default::default(),
                committed_private_context: None,
                resources: None,
                cancellation: Default::default(),
                progress: None,
                members: None,
            })
            .await
            .unwrap();
        let metadata: serde_json::Value =
            serde_json::from_str(prepared.request_metadata().unwrap().content()).unwrap();
        assert_eq!(metadata["maxTokens"], serde_json::Value::Null);
        // Preparing must not poll the operation or access the protected storage.
        drop(prepared);
        session.close().await.unwrap();
    }
}

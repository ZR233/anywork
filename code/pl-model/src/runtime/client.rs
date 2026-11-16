//! The routed facade holds concrete provider clients, without an erased mega-interface.
use super::{InvocationRunner, ModelInvocationContext};
use crate::completion::{
    CompletionFailure, CompletionRequest, CompletionResponse, ModelCompactionRequest,
    ModelCompactionResponse,
};
use crate::model::{ModelCapabilities, ModelInfo};
use crate::protocol::{ProtocolClient, ProtocolEndpoint, WireApi};
use pl_protocol::{PricingMode, Result};

/// One resolved model route. Native capabilities remain available through `protocol_client()`.
#[derive(Debug, Clone)]
pub struct ModelRuntime {
    runner: InvocationRunner,
    context: pl_protocol::ModelContextResolution,
}

impl ModelRuntime {
    /// Constructs the selected account route and freezes its configured accounting policy.
    ///
    /// # Errors
    /// Rejects invalid endpoint or model configuration.
    pub fn from_route(route: &crate::config::ResolvedModelRoute) -> Result<Self> {
        let runtime = Self::new_with_account_id(
            route.account_id.as_str(),
            route.endpoint.clone(),
            route.model.clone(),
        )?
        .with_pricing_mode(route.pricing_mode);
        Ok(Self {
            context: route.context.clone(),
            ..runtime
        })
    }

    /// Binds a route with its stable account identity.
    /// # Errors
    /// Returns invalid model or endpoint configuration.
    pub fn new_with_account_id(
        id: impl Into<String>,
        endpoint: ProtocolEndpoint,
        model: ModelInfo,
    ) -> Result<Self> {
        Ok(Self {
            context: {
                let mut context = model.resolve_context(None);
                context.auto_compact_limit = None;
                context
            },
            runner: InvocationRunner::new_with_account_id(id, endpoint, model)?,
        })
    }

    /// Explicit native access, preserving the concrete vendor types.
    pub fn protocol_client(&self) -> ProtocolClient<'_> {
        ProtocolClient::new(self.runner.endpoint(), &self.runner)
    }
    pub fn model(&self) -> &ModelInfo {
        self.runner.model()
    }
    pub fn endpoint(&self) -> &ProtocolEndpoint {
        self.runner.endpoint()
    }
    pub fn account_id(&self) -> &str {
        self.runner.account_id()
    }
    pub fn effective_model_capabilities(&self) -> ModelCapabilities {
        self.runner.effective_model_capabilities()
    }
    pub fn connection_fingerprint(&self) -> u64 {
        self.runner.connection_fingerprint()
    }

    pub fn context(&self) -> &pl_protocol::ModelContextResolution {
        &self.context
    }

    pub(super) fn project_request_options(
        &self,
        request: &CompletionRequest,
        thread_id: &str,
    ) -> Result<String> {
        self.runner.project_request_options(request, thread_id)
    }

    pub(super) fn validate_recovery_input(
        &self,
        request: &CompletionRequest,
        thread_id: &str,
    ) -> Result<()> {
        self.runner.validate_recovery_input(request, thread_id)
    }

    /// Freezes this account route's monetary accounting choice for subsequent invocations.
    pub fn with_pricing_mode(mut self, mode: PricingMode) -> Self {
        self.runner.pricing_mode = mode;
        self
    }

    /// Uses an explicit clock for reproducible tariff selection and replay simulations.
    pub fn with_clock(mut self, clock: std::sync::Arc<dyn super::InferenceClock>) -> Self {
        self.runner.clock = clock;
        self
    }

    /// Executes a provider-neutral request.
    /// # Errors
    /// Returns a typed failure with any usage observed before termination.
    pub async fn complete(
        &self,
        request: CompletionRequest,
        context: ModelInvocationContext,
    ) -> std::result::Result<CompletionResponse, CompletionFailure> {
        self.runner.complete(request, context).await
    }

    /// Returns a real remote compaction capability only when the endpoint declares support.
    pub fn compaction(&self) -> Option<RemoteCompaction<'_>> {
        let runner = &self.runner;
        (runner.endpoint().service_capabilities.remote_compaction
            && runner.model().binding.transport.protocol == WireApi::Responses)
            .then_some(RemoteCompaction { runner })
    }
}

/// An available remote compaction operation; unsupported adapters never implement it.
#[derive(Debug, Clone, Copy)]
pub struct RemoteCompaction<'a> {
    runner: &'a InvocationRunner,
}

/// A validated native replacement and its observed service accounting.
#[derive(Debug)]
pub struct NativeCompactionCheckpoint {
    pub timing: Option<pl_protocol::InferenceTiming>,
    pub item: crate::completion::ModelContextItem,
    pub accounting: pl_protocol::InferenceAccounting,
    pub model_observation: Option<pl_protocol::InferenceModelObservation>,
}

impl RemoteCompaction<'_> {
    /// Executes the adapter's native compaction and validates the returned checkpoint.
    ///
    /// # Errors
    /// Rejects completion-only media/sampling options; preserves observed usage when
    /// transport or checkpoint validation fails.
    pub async fn checkpoint(
        &self,
        request: CompletionRequest,
        context: ModelInvocationContext,
    ) -> std::result::Result<NativeCompactionCheckpoint, CompletionFailure> {
        if !request.attachments.is_empty()
            || !request.prepared_content.is_empty()
            || request.temperature.is_some()
            || request.max_tokens.is_some()
            || request.tool_choice != "auto"
        {
            return Err(pl_protocol::PureError::ConfigError(
                "native compaction does not support completion-only media or sampling options"
                    .into(),
            )
            .into());
        }
        let response = self
            .complete(
                ModelCompactionRequest {
                    mode: crate::completion::OpenAiCompactionMode::RemoteV2,
                    prefix: request,
                },
                context,
            )
            .await?;
        let item =
            crate::completion::remote_compaction_checkpoint(response.input).map_err(|source| {
                CompletionFailure {
                    source: Box::new(source),
                    accounting: Box::new(response.accounting.clone()),
                    timing: response.timing,
                    model_observation: response.model_observation.clone().map(Box::new),
                    presentation_items: Vec::new(),
                    partial_progress: None,
                    cancelled: false,
                }
            })?;
        Ok(NativeCompactionCheckpoint {
            timing: response.timing,
            item,
            accounting: response.accounting,
            model_observation: response.model_observation,
        })
    }

    /// Compacts provider context using the declared native protocol.
    /// # Errors
    /// Returns transport or compaction protocol failures.
    pub async fn complete(
        &self,
        request: ModelCompactionRequest,
        context: ModelInvocationContext,
    ) -> std::result::Result<ModelCompactionResponse, CompletionFailure> {
        super::compaction::compact_context(self.runner, request, context).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_core::{
        context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource},
        model::{Model, ModelFailureKind, ModelRequest, ToolCallMode},
    };
    use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
    use serde_json::json;

    fn native_runtime(fixture: &FixtureServer, alias: &str, model: &str) -> ModelRuntime {
        let mut info = ModelInfo::compatible("catalog-model");
        info.binding
            .set_transport(crate::model::ModelTransportProfile::responses_http());
        info.binding.request.api_model = Some(alias.into());
        if let crate::model::ModelProtocolOptions::Responses(options) =
            &mut info.binding.request.protocol
        {
            options.max_tokens_field = crate::model::ResponsesMaxTokensField::MaxOutputTokens;
        }
        let mut runtime = ModelRuntime::new_with_account_id(
            "fixture",
            ProtocolEndpoint::compatible("fixture", fixture.base_url()),
            info,
        )
        .unwrap();
        runtime.runner = runtime.runner.with_native_body(
            serde_json::from_value(json!({"model":model,
                "store":false,"conversation":null,"previous_response_id":null}))
            .unwrap(),
        );
        runtime
    }

    fn request(attempt: &str) -> ModelRequest {
        ModelRequest {
            thread_id: "native-thread".into(),
            turn_id: "native-turn".into(),
            attempt_id: attempt.into(),
            context: ContextSnapshot {
                revision: 0,
                records: vec![ContextRecord {
                    id: format!("{attempt}:input"),
                    turn_id: Some("native-turn".into()),
                    source: ContextSource::User,
                    content: vec![ContextContent::Text {
                        text: attempt.into(),
                    }],
                    tool_calls: Vec::new(),
                }]
                .into(),
            },
            tools: Vec::new().into(),
            tool_call_mode: ToolCallMode::Sequential,
            solo_tool_ids: Vec::new().into(),
            recovery_parameters: None,
            committed_private_context: None,
            resources: None,
            cancellation: Default::default(),
            progress: None,
            members: None,
        }
    }

    #[tokio::test]
    async fn recovery_omitted_typed_limit_accepts_only_the_same_final_native_output_limit() {
        let fixture = FixtureServer::start(vec![Step::prompt(
            Protocol::ResponsesHttp,
            "native restored limit",
            0,
            Reply::Sse(responses_text("done", "native-limit", "native-a")),
        )])
        .await
        .unwrap();
        let runtime = native_runtime(&fixture, "api-a", "native-a");
        let source = super::super::ThreadModel::new_current(runtime.clone(), None);
        let mut session = source.open_session().await.unwrap();
        let prepared = session.prepare(request("source-limit")).await.unwrap();
        let parameters = prepared.request_metadata().unwrap().clone();
        let limit = super::super::model_request_receipt(&parameters)
            .unwrap()
            .max_tokens
            .unwrap();
        drop(prepared);
        session.close().await.unwrap();
        let mut info = runtime.model().clone();
        if let crate::model::ModelProtocolOptions::Responses(options) =
            &mut info.binding.request.protocol
        {
            options.max_tokens_field = crate::model::ResponsesMaxTokensField::Omit;
        }
        let runtime =
            ModelRuntime::new_with_account_id("fixture", runtime.endpoint().clone(), info).unwrap();
        for supplement in [
            json!({}),
            json!({"max_output_tokens":limit-1}),
            json!({"max_tokens":limit}),
            json!({"max_tool_calls":limit}),
            json!({"max_output_tokens":limit,"max_completion_tokens":limit}),
        ] {
            let mut current = runtime.clone();
            let mut native = supplement.as_object().unwrap().clone();
            native.insert("model".into(), json!("native-a"));
            current.runner = current.runner.with_native_body(native);
            let model = super::super::ThreadModel::new_current(current, None);
            let mut session = model.open_session().await.unwrap();
            let mut resumed = request("bad native limit");
            resumed.recovery_parameters = Some(parameters.clone());
            let error = match session.prepare(resumed).await {
                Err(error) => error,
                Ok(_) => panic!("invalid native limit admitted: {supplement}"),
            };
            assert_eq!(error.kind, ModelFailureKind::IncompatibleContext);
            session.close().await.unwrap();
        }
        assert!(fixture.recorded().is_empty());
        let mut current = runtime;
        current.runner = current.runner.with_native_body(
            serde_json::from_value(json!({"model":"native-a","max_output_tokens":limit})).unwrap(),
        );
        let model = super::super::ThreadModel::new_current(current, None);
        let mut session = model.open_session().await.unwrap();
        let mut resumed = request("native restored limit");
        resumed.recovery_parameters = Some(parameters);
        session
            .prepare(resumed)
            .await
            .unwrap()
            .execute()
            .await
            .unwrap();
        session.close().await.unwrap();
        let recorded = fixture.finish().await.unwrap();
        assert_eq!(recorded.len(), 1);
        assert_eq!(recorded[0].body["max_output_tokens"], limit);
        assert_eq!(recorded[0].body["model"], "native-a");
    }

    #[tokio::test]
    async fn current_receipt_and_recovery_use_the_final_native_overlay_model() {
        let fixture = FixtureServer::start(vec![
            Step::prompt(
                Protocol::ResponsesHttp,
                "same native",
                0,
                Reply::Sse(responses_text("done", "native-0", "native-a")),
            ),
            Step::prompt(
                Protocol::ResponsesHttp,
                "same native new alias",
                1,
                Reply::Sse(responses_text("done", "native-1", "native-a")),
            ),
        ])
        .await
        .unwrap();
        let source = super::super::ThreadModel::new_current(
            native_runtime(&fixture, "api-a", "native-a"),
            None,
        );
        let mut session = source.open_session().await.unwrap();
        let prepared = session.prepare(request("source")).await.unwrap();
        let parameters = prepared.request_metadata().unwrap().clone();
        assert_eq!(
            super::super::model_request_receipt(&parameters)
                .unwrap()
                .sent_model
                .as_deref(),
            Some("native-a")
        );
        drop(prepared);
        session.close().await.unwrap();
        for extra in [
            json!({"store":true}),
            json!({"conversation":"unconfirmed"}),
            json!({"previous_response_id":"old-response"}),
            json!({"prompt":{"id":"old-prompt"}}),
        ] {
            let mut runtime = native_runtime(&fixture, "api-a", "native-a");
            let mut native = serde_json::Map::from_iter([("model".into(), json!("native-a"))]);
            native.extend(extra.as_object().unwrap().clone());
            runtime.runner = runtime.runner.with_native_body(native);
            let model = super::super::ThreadModel::new_current(runtime, None);
            let mut session = model.open_session().await.unwrap();
            let mut resumed = request("unsafe native effect");
            resumed.recovery_parameters = Some(parameters.clone());
            let error = match session.prepare(resumed).await {
                Err(error) => error,
                Ok(_) => panic!("unsafe native effect admitted"),
            };
            assert_eq!(error.kind, ModelFailureKind::IncompatibleContext);
            session.close().await.unwrap();
        }
        let incompatible = super::super::ThreadModel::new_current(
            native_runtime(&fixture, "api-a", "native-b"),
            None,
        );
        let mut session = incompatible.open_session().await.unwrap();
        let mut changed = request("changed native");
        changed.recovery_parameters = Some(parameters.clone());
        let error = match session.prepare(changed).await {
            Err(error) => error,
            Ok(_) => panic!("native model changed without rejection"),
        };
        assert_eq!(error.kind, ModelFailureKind::IncompatibleContext);
        session.close().await.unwrap();
        assert!(fixture.recorded().is_empty());
        for (alias, text) in [("api-a", "same native"), ("api-b", "same native new alias")] {
            let model = super::super::ThreadModel::new_current(
                native_runtime(&fixture, alias, "native-a"),
                None,
            );
            let mut session = model.open_session().await.unwrap();
            let mut resumed = request(text);
            resumed.recovery_parameters = Some(parameters.clone());
            session
                .prepare(resumed)
                .await
                .unwrap()
                .execute()
                .await
                .unwrap();
            session.close().await.unwrap();
        }
        let recorded = fixture.finish().await.unwrap();
        assert_eq!(recorded.len(), 2);
        assert!(
            recorded
                .iter()
                .all(|request| request.body["model"] == "native-a")
        );
    }
}

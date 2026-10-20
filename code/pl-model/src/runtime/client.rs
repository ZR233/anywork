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
        let prompt_cache_key = context.prompt_cache_key();
        let response = self
            .complete(
                ModelCompactionRequest {
                    mode: crate::completion::OpenAiCompactionMode::RemoteV2,
                    prefix: request,
                    prompt_cache_key,
                },
                context,
            )
            .await?;
        let item =
            crate::completion::remote_compaction_checkpoint(response.input).map_err(|source| {
                CompletionFailure {
                    source: Box::new(source),
                    accounting: Box::new(response.accounting.clone()),
                    model_observation: response.model_observation.clone().map(Box::new),
                    presentation_items: Vec::new(),
                    partial_progress: None,
                    cancelled: false,
                }
            })?;
        Ok(NativeCompactionCheckpoint {
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

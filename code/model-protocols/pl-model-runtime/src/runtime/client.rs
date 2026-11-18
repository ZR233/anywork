//! Frozen model route, client construction and capability access.
use super::ModelInvocationContext;
use crate::completion::{
    CompletionFailure, CompletionRequest, ModelCompactionRequest, ModelCompactionResponse,
};
use crate::model::PricingMode;
use crate::model::{ModelCapabilities, ModelInfo};
use crate::protocol::{FileUploadCapability, ProtocolEndpoint, WireApi};
use pl_model_types::files::UploadFile;
use pl_protocol::PureError;
use pl_protocol::Result;
use std::sync::Arc;

/// One frozen account/model route and its shared HTTP client.
#[derive(Clone)]
pub struct ModelRuntime {
    pub(super) account_id: String,
    pub(super) endpoint: ProtocolEndpoint,
    pub(super) http_client: reqwest::Client,
    pub(super) model: ModelInfo,
    pub(super) clock: Arc<dyn super::InferenceClock>,
    pub(super) pricing_mode: PricingMode,
    pub(super) upload: Option<UploadFile>,
    context: crate::model::ModelContextResolution,
}

impl ModelRuntime {
    /// Constructs the selected account route and freezes its configured accounting policy.
    ///
    /// # Errors
    /// Rejects invalid endpoint or model configuration.
    pub fn bind_route(
        route: &crate::config::ResolvedModelRoute,
        upload: Option<UploadFile>,
    ) -> Result<Self> {
        let runtime = Self::bind(
            route.account_id.as_str(),
            route.endpoint.clone(),
            route.model.clone(),
            upload,
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
    pub fn bind(
        account_id: impl Into<String>,
        endpoint: ProtocolEndpoint,
        model: ModelInfo,
        upload: Option<UploadFile>,
    ) -> Result<Self> {
        if endpoint.service_capabilities.files != FileUploadCapability::None && upload.is_none() {
            return Err(PureError::ConfigError(
                "endpoint declares file upload without a protocol implementation".into(),
            ));
        }
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

        let mut context = model.resolve_context(None);
        context.auto_compact_limit = None;
        Ok(Self {
            context,
            account_id,
            endpoint,
            http_client,
            upload,
            model,
            clock: Arc::new(super::clock::SystemInferenceClock),
            pricing_mode: crate::model::PricingMode::Catalog,
        })
    }

    pub fn model(&self) -> &ModelInfo {
        &self.model
    }
    pub fn endpoint(&self) -> &ProtocolEndpoint {
        &self.endpoint
    }
    pub fn account_id(&self) -> &str {
        &self.account_id
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

    pub fn context(&self) -> &crate::model::ModelContextResolution {
        &self.context
    }

    /// Freezes this account route's monetary accounting choice for subsequent invocations.
    pub fn with_pricing_mode(mut self, mode: PricingMode) -> Self {
        self.pricing_mode = mode;
        self
    }

    /// Uses an explicit clock for reproducible tariff selection and replay simulations.
    pub fn with_clock(mut self, clock: std::sync::Arc<dyn super::InferenceClock>) -> Self {
        self.clock = clock;
        self
    }

    /// Returns a real remote compaction capability only when the endpoint declares support.
    pub fn compaction(&self) -> Option<RemoteCompaction<'_>> {
        let runtime = self;
        (runtime.endpoint().service_capabilities.remote_compaction
            && runtime.model().binding.transport.protocol == WireApi::Responses)
            .then_some(RemoteCompaction { runtime })
    }
}

/// Native compaction capability exposed only by endpoints that declare support.
#[derive(Debug, Clone, Copy)]
pub struct RemoteCompaction<'a> {
    runtime: &'a ModelRuntime,
}

/// A validated native replacement and its observed service accounting.
#[derive(Debug)]
pub struct NativeCompactionCheckpoint {
    pub timing: Option<crate::completion::InferenceTiming>,
    pub item: crate::completion::ModelContextItem,
    pub accounting: crate::model::InferenceAccounting,
    pub model_observation: Option<crate::completion::InferenceModelObservation>,
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
        super::compaction::compact_context(self.runtime, request, context).await
    }
}

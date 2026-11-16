//! Provider-backed implementation of the protocol-independent Thread model ports.
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};

use pl_core::{
    context::OpaquePayload,
    model::{
        DynModelSession, Model, ModelError, ModelFailureKind, ModelRequest,
        ModelSession as CoreModelSession, ModelUsage, PreparedModelCall,
    },
};

use super::{ModelInvocationContext, ModelRuntime, ModelSession};
use crate::completion::{ReasoningConfig, ToolSpec};

mod compaction;
pub use compaction::{
    TextCompactionBinding, ThreadCompaction, ThreadCompactionDecision, ThreadCompactionOptions,
    ThreadCompactionStrategy, migrate_legacy_compaction,
};
mod codec;
mod media;
pub(crate) mod member;
pub use member::{ModelMemberReceipt, ModelMemberState, model_member_receipt};
pub mod migration;
pub(crate) mod progress;
mod receipt;
mod recovery;
pub(super) use codec::{FRAME_VERSION, LEGACY_FRAME_VERSION};
pub use media::{
    ToolAttachment, attachment_content, decode_attachment, validate_attachment_content,
};
pub(super) use receipt::{FAILURE_RECEIPT_VERSION, REQUEST_RECEIPT_VERSION};
pub use receipt::{
    ModelCallBinding, ModelFailureReceipt, ModelRequestReceipt, ModelResponseReceipt,
    model_failure_receipt, model_request_receipt, model_response_receipt,
};

/// Model factory sharing clients while creating a private physical session for each Thread.
#[derive(Debug, Clone)]
pub struct ThreadModel {
    runtime: ModelRuntime,
    reasoning: Option<ReasoningConfig>,
    purpose: String,
    hosted_tools: Arc<[super::HostedTool]>,
    contract: codec::FrameContract,
}

struct EncodedRequest {
    completion: crate::completion::CompletionRequest,
    tool_bindings: BTreeMap<String, codec::ToolBinding>,
    sent_model: Option<String>,
}

impl ThreadModel {
    /// Freezes model parameters before the Thread session is opened.
    pub fn new(runtime: ModelRuntime, reasoning: Option<ReasoningConfig>) -> Self {
        Self {
            runtime,
            reasoning,
            purpose: "turn".into(),
            hosted_tools: Vec::new().into(),
            contract: codec::FrameContract::Legacy,
        }
    }

    /// Builds the independent current contract without switching existing production factories.
    /// This factory consumes only explicitly upgraded assistant frames and emits version 6.
    pub fn new_current(runtime: ModelRuntime, reasoning: Option<ReasoningConfig>) -> Self {
        Self {
            contract: codec::FrameContract::Current,
            ..Self::new(runtime, reasoning)
        }
    }
    /// Stable route provenance, independent of instruction, tool and execution revisions.
    pub fn route_identity(&self) -> String {
        receipt::ModelCallBinding::capture(&self.runtime, &self.purpose).route_identity()
    }

    /// Configures provider-executed capabilities; these never create local tool executors.
    pub fn with_hosted_tools(mut self, tools: Vec<super::HostedTool>) -> Self {
        self.hosted_tools = tools.into();
        self
    }

    /// Sets a diagnostic purpose for this independent session factory; it grants no execution permissions.
    pub fn with_purpose(mut self, purpose: impl Into<String>) -> Self {
        self.purpose = purpose.into();
        self
    }
    /// One encoding path for execution, previews and reduction, including every tool and media.
    async fn encode_request(&self, request: &ModelRequest) -> Result<EncodedRequest, ModelError> {
        let context_error = |mut error: ModelError| {
            if request.recovery_parameters.is_some() {
                error.kind = ModelFailureKind::IncompatibleContext;
            }
            error
        };
        self.validate_context_origin(&request.context)
            .map_err(context_error)?;
        let mut encoded =
            codec::request(request, &self.runtime, self.contract).map_err(context_error)?;
        encoded.reasoning = self.reasoning.clone();
        if self.runtime.endpoint().chatgpt_session.is_none() {
            encoded.max_tokens = self.runtime.model().max_output_tokens;
        }
        encoded.parallel_tool_calls = request.tool_call_mode
            == pl_core::model::ToolCallMode::Parallel
            && self.runtime.model().capabilities.tools.parallel_tool_calls;
        self.runtime
            .validate_context(&encoded.input)
            .map_err(|error| failure(ModelFailureKind::IncompatibleContext, error))?;
        let mut declarations = codec::declarations(&request.tools).map_err(context_error)?;
        for (tool, declaration) in &mut declarations {
            if request.solo_tool_ids.contains(&tool.tool_id) {
                match declaration {
                    ToolSpec::Function { description, .. }
                    | ToolSpec::Custom { description, .. } => {
                        description.push_str(" This tool must be the only tool call in its model response; never batch it with queries or other tools.");
                    }
                    ToolSpec::ProgrammaticToolCalling | ToolSpec::WebSearch { .. } => {}
                }
            }
        }
        let mut sent_model = None;
        if let Some(parameters) = &request.recovery_parameters {
            sent_model = Some(recovery::apply(
                self,
                request,
                parameters,
                &declarations,
                &mut encoded,
            )?);
        } else {
            encoded.tools = declarations.iter().map(|(_, spec)| spec.clone()).collect();
            for tool in self.hosted_tools.iter() {
                let declaration = tool.declaration();
                if encoded
                    .tools
                    .iter()
                    .any(|existing| existing.name() == declaration.name())
                {
                    return Err(failure(
                        ModelFailureKind::UnsupportedContent,
                        AdapterError::Content(
                            "hosted and local tool declarations have conflicting identities",
                        ),
                    ));
                }
                encoded.tools.push(declaration);
            }
        }
        media::prepare(request, &mut encoded, self.runtime.model()).await?;
        encoded = self.runtime.prepare_request(encoded).map_err(|error| {
            failure(
                if request.recovery_parameters.is_some() {
                    ModelFailureKind::IncompatibleContext
                } else {
                    ModelFailureKind::UnsupportedContent
                },
                error,
            )
        })?;
        if self.contract == codec::FrameContract::Current && sent_model.is_none() {
            sent_model = Some(
                self.runtime
                    .project_request_options(&encoded, &request.thread_id)
                    .map_err(|error| failure(ModelFailureKind::UnsupportedContent, error))?,
            );
        }
        if encoded.frozen_options {
            self.runtime
                .validate_recovery_input(&encoded, &request.thread_id)
                .map_err(|error| failure(ModelFailureKind::IncompatibleContext, error))?;
        }
        let tool_bindings = declarations
            .iter()
            .filter(|(_, spec)| {
                request.recovery_parameters.is_none()
                    || encoded.tools.iter().any(|advertised| {
                        !advertised.is_hosted() && advertised.name() == spec.name()
                    })
            })
            .map(|(tool, spec)| {
                (
                    spec.name().to_owned(),
                    codec::ToolBinding::new(
                        tool.tool_id.clone(),
                        spec,
                        tool.presentation_contract.clone(),
                    ),
                )
            })
            .collect();
        Ok(EncodedRequest {
            completion: encoded,
            tool_bindings,
            sent_model,
        })
    }
}

impl Model for ThreadModel {
    fn open_session(
        &self,
    ) -> impl std::future::Future<Output = Result<DynModelSession, ModelError>> + Send {
        let session = ThreadModelSession {
            runtime: self.runtime.clone(),
            reasoning: self.reasoning.clone(),
            purpose: self.purpose.clone(),
            hosted_tools: self.hosted_tools.clone(),
            physical: ModelSession::default(),
            observed: Arc::new(Mutex::new(None)),
            prompt: super::ThreadPromptMetadata::default(),
            last_compaction_id: None,
            contract: self.contract,
        };
        async move { Ok(DynModelSession::new(session)) }
    }
}

struct ThreadModelSession {
    runtime: ModelRuntime,
    reasoning: Option<ReasoningConfig>,
    purpose: String,
    hosted_tools: Arc<[super::HostedTool]>,
    physical: ModelSession,
    observed: Arc<Mutex<Option<OpaquePayload>>>,
    prompt: super::ThreadPromptMetadata,
    last_compaction_id: Option<String>,
    contract: codec::FrameContract,
}

impl CoreModelSession for ThreadModelSession {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let configuration = ThreadModel {
            runtime: self.runtime.clone(),
            reasoning: self.reasoning.clone(),
            purpose: self.purpose.clone(),
            hosted_tools: self.hosted_tools.clone(),
            contract: self.contract,
        };
        let EncodedRequest {
            completion: encoded,
            tool_bindings: names,
            sent_model,
        } = configuration.encode_request(&request).await?;
        let observed = self
            .observed
            .lock()
            .map_err(|_| failure(ModelFailureKind::Unavailable, AdapterError::Poisoned))?
            .clone();
        if request.recovery_parameters.is_some() || observed != request.committed_private_context {
            self.physical
                .reset_transport()
                .await
                .map_err(|error| failure(ModelFailureKind::Unavailable, error))?;
            *self
                .observed
                .lock()
                .map_err(|_| failure(ModelFailureKind::Unavailable, AdapterError::Poisoned))? =
                None;
        }
        let estimate = crate::completion::estimate_text_input_tokens(&encoded);
        let input_limit = if encoded.frozen_options && encoded.max_tokens.is_some() {
            self.runtime.context().context_window.map(|window| {
                window.saturating_sub(encoded.max_tokens.expect("saved output budget"))
            })
        } else {
            self.runtime.context().input_token_limit
        };
        if estimate
            .zip(input_limit)
            .is_some_and(|(tokens, window)| tokens >= window)
        {
            return Err(failure(
                ModelFailureKind::ContextLimit,
                AdapterError::Content("prepared input exceeds the bound model context window"),
            ));
        }
        let tool_projection = media::tool_projection(self.runtime.model())?;
        let runtime = self.runtime.clone();
        let binding = receipt::ModelCallBinding::capture(&runtime, &self.purpose);
        let compaction_id = request.context.records.iter().rev().find_map(|record| {
            matches!(&record.source, pl_core::context::ContextSource::Runtime { source_id } if source_id == "model.compaction")
                .then(|| record.id.clone())
        });
        let replay_material = encoded
            .replay_spans
            .iter()
            .map(|span| (span.start, &span.output))
            .collect::<Vec<_>>();
        let context_bytes = serde_json::to_vec(&(&encoded.input, replay_material))
            .map_err(|source| failure(ModelFailureKind::UnsupportedContent, source))?;
        let context_hash = pl_core::context::content_hash(&context_bytes);
        let prefix_hash = pl_core::context::content_hash(
            encoded
                .system_prompt
                .as_ref()
                .map(|prompt| prompt.content())
                .unwrap_or_default()
                .as_bytes(),
        );
        let instruction_text = encoded
            .system_prompt
            .as_ref()
            .map(|prompt| prompt.content())
            .unwrap_or_default();
        let prompt = super::prompt_diagnostics(
            &self.prompt,
            super::PromptCacheInput {
                scope: &self.purpose,
                account_id: runtime.account_id(),
                account: runtime.endpoint(),
                model: &runtime.model().model_id,
                instructions: instruction_text,
                prelude_messages: &[],
                context_hash: &context_hash,
                fixed_prefix_section_hashes: BTreeMap::from([("instructions".into(), prefix_hash)]),
                tools: &encoded.tools,
                tool_choice: &encoded.tool_choice,
                parallel_tool_calls: encoded.parallel_tool_calls,
                reasoning: encoded.reasoning.as_ref(),
                output_schema: None,
                service_tier: None,
                compacted: compaction_id.is_some() && self.last_compaction_id != compaction_id,
                prompt_cache_policy: runtime
                    .endpoint()
                    .effective_prompt_cache_policy(runtime.model()),
                updated_at: std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_secs()
                    .min(i64::MAX as u64) as i64,
            },
        )
        .map_err(|source| failure(ModelFailureKind::UnsupportedContent, source))?
        .or_else(|| self.prompt.slots.get(&self.purpose).cloned());
        let request_metadata =
            receipt::request_metadata(&binding, &encoded, prompt.as_ref(), sent_model.as_deref())?;
        if let Some(prompt) = &prompt {
            self.prompt.active_scope = self.purpose.clone();
            self.prompt
                .slots
                .insert(self.purpose.clone(), prompt.clone());
        }
        self.last_compaction_id = compaction_id;
        let usage_binding = pl_core::model::ModelUsageBinding {
            route_identity: Some(binding.route_identity()),
            model: binding.model_id.clone(),
            context_window: binding.context_window,
            max_context_window: binding.max_context_window,
            auto_compact_limit: binding.auto_compact_limit,
        };
        let terminal_progress = request.progress.clone();
        let observed = self.observed.clone();
        let marker = OpaquePayload::new("pl.model.continuation", 1, request.attempt_id.clone())
            .map_err(|error| failure(ModelFailureKind::InvalidResponse, error))?;
        let invocation = ModelInvocationContext::new(self.physical.clone())
            .with_trace_metadata(crate::completion::CompletionTraceContext {
                session_id: request.thread_id.clone(),
                turn_id: request.turn_id.clone(),
                inference_id: request.attempt_id.clone(),
            })
            .with_cancellation(Some(request.cancellation.clone()))
            .with_progress(request.progress.clone())
            .with_members(request.members.clone())
            .with_prompt_cache_scope(super::PromptCacheScope::thread(&request.thread_id));
        let contract = self.contract;
        let (capture, current) = if contract == codec::FrameContract::Current {
            let (handle, current) = super::current::CurrentInvocation::channel(&request.attempt_id);
            (Some(handle), Some(current))
        } else {
            (None, None)
        };
        let invocation = if let Some(current) = &current {
            invocation.with_current(current.clone())
        } else {
            invocation
        };
        let applied_recovery_parameters = request.recovery_parameters.clone();
        let work = async move {
            *observed
                .lock()
                .map_err(|_| failure(ModelFailureKind::Unavailable, AdapterError::Poisoned))? =
                Some(marker.clone());
            let response = runtime
                .complete(encoded, invocation)
                .await
                .map_err(|error| {
                    receipt::failure_error(
                        binding.clone(),
                        error,
                        terminal_progress.as_ref().map(|sender| sender.latest()),
                    )
                })?;
            let output = codec::response(
                codec::ResponseContext {
                    request: &request,
                    names: &names,
                    marker: marker.clone(),
                    binding,
                    compatibility_family: runtime
                        .model()
                        .capabilities
                        .native_context_family
                        .clone(),
                    contract,
                },
                response,
            )?;
            Ok(output)
        };
        let call = if let Some(capture) = capture {
            PreparedModelCall::new_with_current(async move {
                let result = work.await;
                let current = current.expect("current factory").take_final();
                pl_core::model::ModelCallExit { result, current }
            })
            .with_current_capture(capture)
        } else {
            PreparedModelCall::new(work)
        };
        let call = call
            .with_tool_projection(tool_projection)
            .with_request_metadata(request_metadata)
            .with_usage_binding(usage_binding);
        let call = match applied_recovery_parameters {
            Some(parameters) => call.with_applied_recovery_parameters(parameters),
            None => call,
        };
        Ok(match estimate {
            Some(tokens) => call.with_input_estimate(pl_core::model::TokenEstimate {
                tokens,
                accuracy: pl_core::model::EstimateAccuracy::Approximate,
            }),
            None => call,
        })
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        self.physical
            .close()
            .await
            .map_err(|error| failure(ModelFailureKind::Unavailable, error))
    }
}

/// Encodes a stable tool declaration for the Thread adapter without exposing its schema to core.
///
/// # Errors
/// Returns declaration encoding failure.
pub fn thread_tool_declaration(spec: &ToolSpec) -> Result<OpaquePayload, ModelError> {
    let mut value = serde_json::to_value(spec)
        .map_err(|error| failure(ModelFailureKind::UnsupportedContent, error))?;
    crate::completion::canonicalize_json(&mut value);
    OpaquePayload::new("pl.model.tool-spec", 1, value.to_string())
        .map_err(|error| failure(ModelFailureKind::UnsupportedContent, error))
}

#[derive(Debug, thiserror::Error)]
enum AdapterError {
    #[error("model session observation state is poisoned")]
    Poisoned,
    #[error("unsupported or invalid model history: {0}")]
    Content(&'static str),
}

pub(super) fn failure(
    kind: ModelFailureKind,
    source: impl std::error::Error + Send + Sync + 'static,
) -> ModelError {
    ModelError {
        details: None,
        kind,
        usage: Box::default(),
        source: Some(Box::new(source)),
    }
}

fn usage(report: &pl_protocol::UsageReport) -> ModelUsage {
    crate::model::usage::model_usage(report)
}

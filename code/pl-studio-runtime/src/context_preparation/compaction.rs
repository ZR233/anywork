//! Model-bound context preparation and compaction admission.
use std::collections::BTreeMap;

use pl_core::{
    model::{ModelError, ModelFailureKind, ToolCallMode},
    thread::{
        context_preparation::{
            ContextPreparation, ContextPreparationHook, ContextPreparationRequest, ContextPreparer,
        },
        extensions::{ExtensionInputs, ExtensionMutation, ExtensionRecord},
    },
};
use pl_model::{
    completion::OpenAiCompactionMode,
    config::ResolvedModelRoute,
    runtime::{
        ThreadCompactionDecision, ThreadCompactionOptions, ThreadCompactionStrategy, ThreadModel,
    },
};

use super::facts::{append_preview_facts, current_facts};
use super::instructions::{InstructionBinding, instruction_binding, restore_current_instructions};
use super::mode_workflow::{ModePreparation, freeze_mode_for_turn, prepare_workflow};

/// Selects the product summary policy without changing provider capabilities.
fn policy(mode: OpenAiCompactionMode) -> ThreadCompactionOptions {
    ThreadCompactionOptions {
        strategy: match mode {
            OpenAiCompactionMode::Local => ThreadCompactionStrategy::TextSummary,
            OpenAiCompactionMode::RemoteV2 => ThreadCompactionStrategy::PreferNative,
        },
        instructions: include_str!("../prompts/compact.md").into(),
        requirement: "请根据以上完整上下文生成压缩摘要。".into(),
        summary_prefix: "以下是此前对话的压缩摘要。".into(),
        max_output_tokens: None,
    }
}

/// Thread-scoped activation record format written by the Skill tool's main-document load.
///
/// The runtime snapshot derives `activeSkills` from exactly the extensions carrying this format,
/// so clearing that set is the only way to empty the current Skill collection.
const SKILL_VIEW_FORMAT: &str = "pl.tool.skill-view";

/// Binds the policy to the same frozen route as the main model session.
pub(crate) fn preparer(
    route: &ResolvedModelRoute,
    model: ThreadModel,
    mode: OpenAiCompactionMode,
    modes: crate::mode::ThreadModeManager,
    models: &pl_model::config::AgentModelConfig,
) -> ContextPreparer {
    let instruction_binding = instruction_binding(route, &model);
    ContextPreparer::new(StudioCompaction {
        model,
        modes,
        reasoning_effort: route
            .effort
            .as_ref()
            .map(|effort| effort.as_str().to_owned()),
        context_window: route.context.context_window,
        options: policy(mode),
        base_instructions: route
            .model
            .base
            .model_messages
            .instructions_template
            .clone(),
        instruction_binding,
        supports_workflow: route.model.extra.capabilities.supports_function_calling(),
        models: models.clone(),
        role: route.role.clone(),
    })
}

#[derive(Debug)]
struct StudioCompaction {
    model: ThreadModel,
    modes: crate::mode::ThreadModeManager,
    reasoning_effort: Option<String>,
    context_window: Option<u64>,
    options: ThreadCompactionOptions,
    base_instructions: String,
    instruction_binding: InstructionBinding,
    supports_workflow: bool,
    models: pl_model::config::AgentModelConfig,
    role: pl_model::config::AgentRoleId,
}
impl ContextPreparationHook for StudioCompaction {
    async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
        self.prepare_step(request)
            .await
            .unwrap_or_else(|error| ContextPreparation::Failed {
                error,
                mutations: Vec::new(),
            })
    }
}

impl StudioCompaction {
    async fn prepare_step(
        &self,
        mut request: ContextPreparationRequest,
    ) -> Result<ContextPreparation, ModelError> {
        let frozen = request.extensions.clone();
        let mut inputs = ExtensionInputs::capture(
            &frozen,
            &[
                crate::studio::model_route::AGENT_PROFILE_EXTENSION,
                crate::mode::MODE_EXTENSION,
                crate::instruction::INSTRUCTIONS_EXTENSION,
                "studio.instructions.binding",
                crate::workflow_tool::WORKFLOW_EXTENSION,
                crate::plan_tool::PLAN_EXTENSION,
                "studio.workspace",
            ],
        );
        let ModePreparation {
            mode,
            mutations: mode_mutations,
            new_turn,
        } = freeze_mode_for_turn(&mut request, &self.modes)?;
        if mode.as_ref().is_some_and(|mode| mode.workflow().is_some()) && !self.supports_workflow {
            return Err(receipt_error(std::io::Error::other(
                "workflow Mode requires a model supporting function calling",
            )));
        }
        let excluded_tool_ids = if mode.as_ref().is_some_and(|mode| mode.workflow().is_none()) {
            crate::workflow_tool::workflow_tool_ids()
                .into_iter()
                .map(str::to_owned)
                .collect::<Vec<_>>()
        } else {
            Vec::new()
        };
        if !excluded_tool_ids.is_empty() {
            exclude_workflow_tools(&mut request.model, &excluded_tool_ids);
        }
        // Source summarization must see the committed source instructions, not the target repair.
        let source_context = request.committed_context.clone();
        let mut instruction_repair = restore_current_instructions(
            &mut request,
            &self.base_instructions,
            &self.instruction_binding,
            mode.as_deref(),
            mode_mutations,
        )?;
        if let Some(mode) = mode.as_deref().filter(|_| new_turn)
            && let Some(mutation) = prepare_workflow(&mut request, mode)?
        {
            instruction_repair.mutations.push(mutation);
        }
        let facts = current_facts(&request, mode.as_deref())?;
        let unchanged = |inputs| ContextPreparation::Prepared {
            excluded_tool_ids: excluded_tool_ids.clone(),
            inputs,
            instruction_binding: instruction_repair.binding.clone(),
            rejected_mutations: Vec::new(),
            replacement: instruction_repair.replacement.as_ref().map(|repair| {
                pl_core::thread::ReplaceContext {
                    expected_revision: repair.expected_revision,
                    reason: repair.reason,
                    records: repair.records.clone(),
                }
            }),
            facts: facts.clone(),
            mutations: instruction_repair.mutations.clone(),
        };
        inputs.include_keys(&frozen, &[LATEST_RECEIPT]);
        let previous_summary = active_text_summary(&source_context.records, &request.extensions);
        // Check the committed source before the target attempts to encode old tool calls,
        // attachments or provider checkpoints, independent of the two context windows.
        let handoff = self.handoff_source(&source_context.records, previous_summary.as_ref())?;
        if handoff.is_none() {
            if source_context
                .records
                .iter()
                .all(|record| record.source == pl_core::context::ContextSource::Instruction)
            {
                return Ok(unchanged(inputs));
            }
            let mut preview = request.model.clone();
            let mut records = preview.context.records.to_vec();
            // Capacity includes freshly projected state and this step's frozen input.
            append_preview_facts(&mut records, &facts, request.extension_sequence);
            preview.context.records = records.into();
            let decision = self
                .model
                .compaction_decision(
                    &preview,
                    request.previous_usage.as_ref(),
                    request.force_compaction,
                )
                .await?;
            if decision == ThreadCompactionDecision::Keep {
                return Ok(unchanged(inputs));
            }
        }
        let (compactor, reasoning_effort, context_window) = match &handoff {
            Some((model, route)) => (
                model,
                route
                    .effort
                    .as_ref()
                    .map(|effort| effort.as_str().to_owned()),
                route.context.context_window,
            ),
            None => (
                &self.model,
                self.reasoning_effort.clone(),
                self.context_window,
            ),
        };
        let call = CompactionCall {
            inference_id: format!(
                "studio.compaction:{}:{}",
                request.model.attempt_id, request.extension_sequence
            ),
            turn_id: request.model.turn_id.clone(),
            context_window,
            reasoning_effort,
            effort_source: if handoff.is_some() {
                CompactionEffortSource::CurrentModelDefault
            } else {
                CompactionEffortSource::FrozenRoute
            },
            previous_summary,
        };
        let previous = request
            .extensions
            .get(LATEST_RECEIPT)
            .map(|record| record.revision);
        // A committed summary replaces the context that carried the loaded Skill bodies, so the
        // activation extensions it consumed are cleared in the same candidate batch. The deletes
        // ride only on the successful replacement: an unreached, failed, cancelled or rejected
        // preparation keeps its activation set, and historical Skill Items stay durable.
        inputs.include_format(&frozen, SKILL_VIEW_FORMAT);
        let skill_clears = skill_activation_clears(&request.extensions);
        request
            .enter_compacting()
            .await
            .map_err(compaction_admission_error)?;
        let mut model_request = request.model.clone();
        model_request.context = if handoff.is_some() {
            source_context
        } else {
            request.committed_context.clone()
        };
        model_request.attempt_id = call.inference_id.clone();
        let mut options = self.options.clone();
        if handoff.is_some() {
            options.strategy = ThreadCompactionStrategy::PortableTextSummary;
            // Only committed source history is exposed to the auxiliary request.
            model_request.tools = Default::default();
            model_request.solo_tool_ids = Default::default();
        }
        match compactor.compact(model_request, options).await {
            Ok(mut result) => {
                let mut receipt = call.receipt(CompactionAccounting {
                    binding: result.binding,
                    accounting: result.accounting,
                    model_observation: result.model_observation,
                    timing: result.timing,
                });
                receipt.implementation = Some(
                    match result.implementation {
                        ThreadCompactionStrategy::TextSummary
                        | ThreadCompactionStrategy::PortableTextSummary => "textSummary",
                        ThreadCompactionStrategy::PreferNative => "native",
                    }
                    .into(),
                );
                receipt.retained_through_record_id = result
                    .replacement
                    .records
                    .last()
                    .map(|record| record.id.clone());
                if handoff.is_some() {
                    request.committed_context.records = result.replacement.records.clone().into();
                    request.model.context.records = result.replacement.records.clone().into();
                    match restore_current_instructions(
                        &mut request,
                        &self.base_instructions,
                        &self.instruction_binding,
                        mode.as_deref(),
                        Vec::new(),
                    ) {
                        Ok(repair) => {
                            if repair.binding.is_some() {
                                instruction_repair.binding = repair.binding;
                            }
                        }
                        Err(error) => {
                            receipt.error = Some(error.to_string());
                            return failure_with_receipt(error, previous, receipt);
                        }
                    }
                    result.replacement.records = request.committed_context.records.to_vec();
                }
                let mut rejected = receipt.clone();
                rejected.error =
                    Some("context preparation candidate was cancelled or rejected".into());
                receipt.context_summary = match result.implementation {
                    ThreadCompactionStrategy::TextSummary
                    | ThreadCompactionStrategy::PortableTextSummary => {
                        Some(pl_model::runtime::TextCompactionBinding {
                            inference_id: receipt.inference_id.clone(),
                            binding: receipt.binding.clone(),
                            retained_through_record_id: receipt.retained_through_record_id.clone(),
                            portable: result.implementation
                                == ThreadCompactionStrategy::PortableTextSummary,
                        })
                    }
                    ThreadCompactionStrategy::PreferNative => None,
                };
                let rejected_mutations = vec![receipt_mutation(previous, rejected)?];
                let mutation = receipt_mutation(previous, receipt)?;
                Ok(ContextPreparation::Prepared {
                    excluded_tool_ids,
                    inputs,
                    instruction_binding: instruction_repair.binding,
                    rejected_mutations,
                    replacement: Some(result.replacement),
                    facts,
                    mutations: instruction_repair
                        .mutations
                        .into_iter()
                        .chain(skill_clears)
                        .chain(std::iter::once(mutation))
                        .collect(),
                })
            }
            Err(error) => {
                let Some(failure) = pl_model::runtime::model_failure_receipt(&error)? else {
                    return Err(error);
                };
                let mut receipt = call.receipt(CompactionAccounting {
                    binding: failure.binding,
                    accounting: failure.accounting,
                    model_observation: failure.model_observation,
                    timing: failure.timing,
                });
                receipt.error = Some(failure.message);
                failure_with_receipt(error, previous, receipt)
            }
        }
    }
    fn handoff_source(
        &self,
        records: &[pl_core::context::ContextRecord],
        summary: Option<&pl_model::runtime::TextCompactionBinding>,
    ) -> Result<Option<(ThreadModel, ResolvedModelRoute)>, pl_core::model::ModelError> {
        use pl_model::config::{AccountId, ModelRouteConfig, ReasoningEffort};
        let Some(binding) = ThreadModel::latest_replay_binding(records, summary)? else {
            return Ok(None);
        };
        let source_identity = binding.route_identity();
        if source_identity == self.model.route_identity() {
            return Ok(None);
        }
        let resolve = || -> anyhow::Result<_> {
            let account_id = AccountId::new(binding.account_id.clone())?;
            let account = self
                .models
                .accounts
                .get(&account_id)
                .ok_or_else(|| anyhow::anyhow!("compaction source account is unavailable"))?;
            let entry = account
                .effective_catalog(None)?
                .into_iter()
                .find(|entry| entry.model.base.slug == binding.model_id)
                .ok_or_else(|| anyhow::anyhow!("compaction source model is unavailable"))?;
            let route = self.models.resolve_route(
                self.role.clone(),
                &ModelRouteConfig {
                    account_id,
                    model_id: binding.model_id.clone(),
                    effort: entry.model.default_effort().map(ReasoningEffort::new),
                },
            )?;
            crate::studio::delegation::validate_credential(&route)?;
            let model = ThreadModel::new(
                pl_model::runtime::from_route(&route)?,
                route.reasoning_config(),
            );
            anyhow::ensure!(
                model.route_identity() == source_identity,
                "compaction source route no longer matches the committed context"
            );
            Ok((model, route))
        };
        resolve()
            .map(Some)
            .map_err(|source| pl_core::model::ModelError {
                kind: pl_core::model::ModelFailureKind::Unavailable,
                details: None,
                usage: Default::default(),
                source: Some(source.into()),
            })
    }
}

struct CompactionCall {
    inference_id: String,
    turn_id: String,
    context_window: Option<u64>,
    reasoning_effort: Option<String>,
    effort_source: CompactionEffortSource,
    previous_summary: Option<pl_model::runtime::TextCompactionBinding>,
}

struct CompactionAccounting {
    binding: pl_model::runtime::ModelCallBinding,
    accounting: pl_model::model::InferenceAccounting,
    model_observation: Option<crate::InferenceModelObservation>,
    timing: Option<crate::InferenceTiming>,
}

impl CompactionCall {
    fn receipt(self, result: CompactionAccounting) -> CompactionReceipt {
        CompactionReceipt {
            inference_id: self.inference_id,
            binding: result.binding,
            reasoning_effort: self.reasoning_effort,
            requested_service_tier: Some("notApplicable".into()),
            reasoning_effort_source: Some(self.effort_source),
            context_window: self.context_window,
            turn_id: self.turn_id,
            accounting: result.accounting,
            model_observation: result.model_observation,
            timing: result.timing,
            implementation: None,
            error: None,
            retained_through_record_id: None,
            context_summary: self.previous_summary,
        }
    }
}

fn active_text_summary(
    records: &[pl_core::context::ContextRecord],
    extensions: &BTreeMap<String, ExtensionRecord>,
) -> Option<pl_model::runtime::TextCompactionBinding> {
    let record = extensions.get(LATEST_RECEIPT)?;
    // Historical text diagnostics are optional; their absence is not a native replay failure.
    let receipt = decode_receipt(record.payload.version(), record.payload.content()).ok()?;
    // A successful old envelope itself is sufficient provenance; failed old envelopes cannot
    // establish the source of a different summary. Never infer that source from its selector.
    let origin = receipt.context_summary.or_else(|| {
        (receipt.error.is_none() && receipt.implementation.as_deref() == Some("textSummary"))
            .then_some(pl_model::runtime::TextCompactionBinding {
                inference_id: receipt.inference_id,
                binding: receipt.binding,
                retained_through_record_id: receipt.retained_through_record_id,
                portable: false,
            })
    });
    origin.filter(|origin| records.iter().any(|record| {
        record.id == format!("compaction:{}", origin.inference_id)
            && matches!(&record.source, pl_core::context::ContextSource::Runtime { source_id } if source_id == "model.compaction")
            && record.content.iter().any(|content| matches!(content, pl_core::context::ContextContent::Text { .. }))
    }))
}

fn exclude_workflow_tools(
    request: &mut pl_core::model::ModelRequest,
    excluded_tool_ids: &[String],
) {
    // The capacity preview must describe exactly the tool plan the real step will use.
    // `pl_core::tool::opaque::ToolPlan` derives declarations, solo identities and the
    // scheduling mode from one map, and applies `excluded_tool_ids` to that map before a
    // real call. Excluding a tool here therefore has to drop its exclusive-call identity
    // too, and keep the mode consistent with the retained set; otherwise the preview
    // advertises a solo identity whose declaration was excluded.
    request.tools = request
        .tools
        .iter()
        .filter(|tool| !excluded_tool_ids.contains(&tool.tool_id))
        .cloned()
        .collect::<Vec<_>>()
        .into();
    request.solo_tool_ids = request
        .solo_tool_ids
        .iter()
        .filter(|tool_id| !excluded_tool_ids.contains(tool_id))
        .cloned()
        .collect::<Vec<_>>()
        .into();
    // Same rule as the frozen plan: non-empty and every retained tool solo means strictly
    // sequential calls; otherwise only the retained solo tools keep their constraint.
    let every_retained_tool_is_solo = !request.tools.is_empty()
        && request
            .tools
            .iter()
            .all(|tool| request.solo_tool_ids.contains(&tool.tool_id));
    request.tool_call_mode = if every_retained_tool_is_solo {
        ToolCallMode::Sequential
    } else {
        ToolCallMode::Parallel
    };
}

// Reliable admission must complete before the auxiliary model can run.
fn compaction_admission_error(source: pl_core::thread::ThreadError) -> ModelError {
    let kind = match &source {
        pl_core::thread::ThreadError::Cancelled | pl_core::thread::ThreadError::Closed => {
            ModelFailureKind::Cancelled
        }
        _ => ModelFailureKind::Unavailable,
    };
    ModelError {
        kind,
        details: None,
        usage: Default::default(),
        source: Some(Box::new(source)),
    }
}

fn failure_with_receipt(
    error: ModelError,
    previous: Option<u64>,
    receipt: CompactionReceipt,
) -> Result<ContextPreparation, ModelError> {
    Ok(ContextPreparation::Failed {
        error,
        mutations: vec![receipt_mutation(previous, receipt)?],
    })
}

/// Clears every Skill activation record the runtime snapshot currently counts.
///
/// Identity is the observed record id and its exact revision, so the batch only commits while the
/// prepared request is still current; a concurrent activation narrows the CAS and fails the
/// preparation instead of deleting a newer load. Historical Skill and tool Items, the Skill
/// catalog and call permissions are untouched, and later successful loads accumulate again.
fn skill_activation_clears(
    extensions: &BTreeMap<String, ExtensionRecord>,
) -> Vec<ExtensionMutation> {
    extensions
        .iter()
        .filter(|(_, record)| record.payload.format() == SKILL_VIEW_FORMAT)
        .map(|(id, record)| ExtensionMutation::Delete {
            id: id.clone(),
            expected_revision: record.revision,
        })
        .collect()
}

/// Distinguishes the current source-model default from the admitted target route's effort.
#[derive(Debug, Clone, Copy, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) enum CompactionEffortSource {
    FrozenRoute,
    CurrentModelDefault,
}

/// Auxiliary model accounting is retained separately from normal turn-response receipts.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct CompactionReceipt {
    pub inference_id: String,
    pub binding: pl_model::runtime::ModelCallBinding,
    pub reasoning_effort: Option<String>,
    /// Newly recorded compaction requests do not have a selectable tier. Historical
    /// receipts retain absence so reprojecting them does not change a durable call hash.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub requested_service_tier: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reasoning_effort_source: Option<CompactionEffortSource>,
    pub context_window: Option<u64>,
    pub turn_id: String,
    pub accounting: pl_model::model::InferenceAccounting,
    pub timing: Option<crate::InferenceTiming>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model_observation: Option<crate::InferenceModelObservation>,
    pub implementation: Option<String>,
    pub error: Option<String>,
    /// The replacement's retained tail predates this summary, despite appearing after it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retained_through_record_id: Option<String>,
    /// At most one successful text-summary origin still present in the committed context.
    /// A later failed auxiliary call must not overwrite the provenance of unchanged history.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context_summary: Option<pl_model::runtime::TextCompactionBinding>,
}

impl CompactionReceipt {
    /// v4 retains the executor's timing and explicit first-content provenance.
    pub(crate) const VERSION: u32 = 4;

    pub(crate) fn into_payload(
        self,
    ) -> Result<pl_core::context::OpaquePayload, pl_core::model::ModelError> {
        let payload = serde_json::to_string(&self).map_err(receipt_error)?;
        pl_core::context::OpaquePayload::new("pl.studio.compaction", Self::VERSION, payload)
            .map_err(receipt_error)
    }
}
fn receipt_mutation(
    expected_revision: Option<u64>,
    receipt: CompactionReceipt,
) -> Result<ExtensionMutation, pl_core::model::ModelError> {
    let payload = receipt.into_payload()?;
    Ok(ExtensionMutation::Put {
        id: LATEST_RECEIPT.into(),
        expected_revision,
        payload,
    })
}
pub(super) fn receipt_error(
    source: impl std::error::Error + Send + Sync + 'static,
) -> pl_core::model::ModelError {
    pl_core::model::ModelError {
        kind: pl_core::model::ModelFailureKind::InvalidResponse,
        details: None,
        usage: Default::default(),
        source: Some(Box::new(source)),
    }
}

/// Ordinary consumers only accept the prepared current receipt.
pub(crate) fn decode_receipt(version: u32, content: &str) -> anyhow::Result<CompactionReceipt> {
    anyhow::ensure!(
        version == CompactionReceipt::VERSION,
        "unsupported compaction receipt version"
    );
    Ok(serde_json::from_str(content)?)
}

#[cfg(test)]
#[path = "compaction_tests.rs"]
mod tests;

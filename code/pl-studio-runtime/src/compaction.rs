//! Studio wording for model-owned context compaction.
pub(crate) const LATEST_RECEIPT: &str = "studio.compaction.latest";

use pl_model::{
    completion::OpenAiCompactionMode,
    runtime::{ThreadCompactionOptions, ThreadCompactionStrategy},
};

/// Selects the product summary policy without changing provider capabilities.
pub(crate) fn policy(mode: OpenAiCompactionMode) -> ThreadCompactionOptions {
    ThreadCompactionOptions {
        strategy: match mode {
            OpenAiCompactionMode::Local => ThreadCompactionStrategy::TextSummary,
            OpenAiCompactionMode::RemoteV2 => ThreadCompactionStrategy::PreferNative,
        },
        instructions: include_str!("prompts/compact.md").into(),
        requirement: "请根据以上完整上下文生成压缩摘要。".into(),
        summary_prefix: "以下是此前对话的压缩摘要。".into(),
        max_output_tokens: None,
    }
}

use pl_core::thread::{
    context_preparation::{
        ContextPreparation, ContextPreparationHook, ContextPreparationRequest, ContextPreparer,
    },
    extensions::{ExtensionInputs, ExtensionMutation, ExtensionRecord, InstructionRevisionBinding},
};
use pl_model::{config::ResolvedModelRoute, runtime::ThreadModel};
use std::collections::BTreeMap;

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
) -> Result<Option<ContextPreparer>, pl_model::PureError> {
    let instruction_binding = instruction_binding(route, &model);
    Ok(Some(ContextPreparer::new(StudioCompaction {
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
    })))
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
    async fn before_step(&self, mut request: ContextPreparationRequest) -> ContextPreparation {
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
        } = match freeze_mode_for_turn(&mut request, &self.modes) {
            Ok(candidate) => candidate,
            Err(error) => {
                return ContextPreparation::Failed {
                    error,
                    mutations: vec![],
                };
            }
        };
        if mode.as_ref().is_some_and(|mode| mode.workflow().is_some()) && !self.supports_workflow {
            return ContextPreparation::Failed {
                error: receipt_error(std::io::Error::other(
                    "workflow Mode requires a model supporting function calling",
                )),
                mutations: vec![],
            };
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
            // The capacity preview must describe exactly the tool plan the real step will use.
            // `pl_core::tool::opaque::ToolPlan` derives declarations, solo identities and the
            // scheduling mode from one map, and applies `excluded_tool_ids` to that map before a
            // real call. Excluding a tool here therefore has to drop its exclusive-call identity
            // too, and keep the mode consistent with the retained set; otherwise the preview
            // advertises a solo identity whose declaration was excluded.
            request.model.tools = request
                .model
                .tools
                .iter()
                .filter(|tool| !excluded_tool_ids.contains(&tool.tool_id))
                .cloned()
                .collect::<Vec<_>>()
                .into();
            request.model.solo_tool_ids = request
                .model
                .solo_tool_ids
                .iter()
                .filter(|tool_id| !excluded_tool_ids.contains(tool_id))
                .cloned()
                .collect::<Vec<_>>()
                .into();
            // Same rule as the frozen plan: non-empty and every retained tool solo means strictly
            // sequential calls; otherwise only the retained solo tools keep their constraint.
            let every_retained_tool_is_solo = !request.model.tools.is_empty()
                && request
                    .model
                    .tools
                    .iter()
                    .all(|tool| request.model.solo_tool_ids.contains(&tool.tool_id));
            request.model.tool_call_mode = if every_retained_tool_is_solo {
                pl_core::model::ToolCallMode::Sequential
            } else {
                pl_core::model::ToolCallMode::Parallel
            };
        }
        // Source summarization must see the committed source instructions, not the target repair.
        let source_context = request.committed_context.clone();
        let mut instruction_repair = match restore_current_instructions(
            &mut request,
            &self.base_instructions,
            &self.instruction_binding,
            mode.as_deref(),
            mode_mutations,
        ) {
            Ok(repair) => repair,
            Err(error) => {
                return ContextPreparation::Failed {
                    error,
                    mutations: vec![],
                };
            }
        };
        match prepare_workflow(&mut request, new_turn) {
            Ok(Some(mutation)) => instruction_repair.mutations.push(mutation),
            Ok(None) => {}
            Err(error) => {
                return ContextPreparation::Failed {
                    error,
                    mutations: vec![],
                };
            }
        }
        let facts = match current_facts(&request) {
            Ok(facts) => facts,
            Err(error) => {
                return ContextPreparation::Failed {
                    error,
                    mutations: vec![],
                };
            }
        };
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
        let handoff = match self.handoff_source(&source_context.records, previous_summary.as_ref())
        {
            Ok(source) => source,
            Err(error) => {
                return ContextPreparation::Failed {
                    error,
                    mutations: vec![],
                };
            }
        };
        if handoff.is_none() {
            if source_context
                .records
                .iter()
                .all(|record| record.source == pl_core::context::ContextSource::Instruction)
            {
                return unchanged(inputs);
            }
            let mut preview = request.model.clone();
            let mut records = preview.context.records.to_vec();
            // Capacity includes freshly projected state and this step's frozen input.
            append_preview_facts(&mut records, &facts, request.extension_sequence);
            preview.context.records = records.into();
            match self
                .model
                .compaction_decision(
                    &preview,
                    request.previous_usage.as_ref(),
                    request.force_compaction,
                )
                .await
            {
                Ok(pl_model::runtime::ThreadCompactionDecision::Keep) => return unchanged(inputs),
                Ok(pl_model::runtime::ThreadCompactionDecision::Compact) => {}
                Err(error) => {
                    return ContextPreparation::Failed {
                        error,
                        mutations: vec![],
                    };
                }
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
        let turn_id = request.model.turn_id.clone();
        let id = format!(
            "studio.compaction:{}:{}",
            request.model.attempt_id, request.extension_sequence
        );
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
        if let Err(source) = request.enter_compacting().await {
            // No provider work is allowed before reliable start admission. Keep the original
            // owner/storage error as the cause; it is not a malformed model response.
            let kind = match &source {
                pl_core::thread::ThreadError::Cancelled | pl_core::thread::ThreadError::Closed => {
                    pl_core::model::ModelFailureKind::Cancelled
                }
                _ => pl_core::model::ModelFailureKind::Unavailable,
            };
            return ContextPreparation::Failed {
                error: pl_core::model::ModelError {
                    kind,
                    details: None,
                    usage: Default::default(),
                    source: Some(Box::new(source)),
                },
                mutations: Vec::new(),
            };
        }
        let mut model_request = request.model.clone();
        model_request.context = if handoff.is_some() {
            source_context
        } else {
            request.committed_context.clone()
        };
        model_request.attempt_id = id.clone();
        let mut options = self.options.clone();
        if handoff.is_some() {
            options.strategy = ThreadCompactionStrategy::PortableTextSummary;
            // Only committed source history is exposed to the auxiliary request.
            model_request.tools = Default::default();
            model_request.solo_tool_ids = Default::default();
        }
        match compactor.compact(model_request, options).await {
            Ok(mut result) => {
                let mut receipt = CompactionReceipt {
                    inference_id: id.clone(),
                    binding: result.binding,
                    reasoning_effort,
                    requested_service_tier: Some("notApplicable".into()),
                    reasoning_effort_source: Some(if handoff.is_some() {
                        CompactionEffortSource::CurrentModelDefault
                    } else {
                        CompactionEffortSource::FrozenRoute
                    }),
                    context_window,
                    turn_id: turn_id.clone(),
                    accounting: result.accounting,
                    model_observation: result.model_observation,
                    timing: result.timing,
                    implementation: Some(
                        match result.implementation {
                            ThreadCompactionStrategy::TextSummary
                            | ThreadCompactionStrategy::PortableTextSummary => "textSummary",
                            ThreadCompactionStrategy::PreferNative => "native",
                        }
                        .into(),
                    ),
                    error: None,
                    retained_through_record_id: result
                        .replacement
                        .records
                        .last()
                        .map(|record| record.id.clone()),
                    context_summary: previous_summary.clone(),
                };
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
                            inference_id: id.clone(),
                            binding: receipt.binding.clone(),
                            retained_through_record_id: receipt.retained_through_record_id.clone(),
                            portable: result.implementation
                                == ThreadCompactionStrategy::PortableTextSummary,
                        })
                    }
                    ThreadCompactionStrategy::PreferNative => None,
                };
                let rejected_mutations = match receipt_mutation(previous, rejected) {
                    Ok(mutation) => vec![mutation],
                    Err(error) => {
                        return ContextPreparation::Failed {
                            error,
                            mutations: vec![],
                        };
                    }
                };
                match receipt_mutation(previous, receipt) {
                    Ok(mutation) => ContextPreparation::Prepared {
                        excluded_tool_ids: excluded_tool_ids.clone(),
                        inputs,
                        instruction_binding: instruction_repair.binding,
                        rejected_mutations,
                        replacement: Some(result.replacement),
                        facts,
                        mutations: instruction_repair
                            .mutations
                            .clone()
                            .into_iter()
                            .chain(skill_clears)
                            .chain(std::iter::once(mutation))
                            .collect(),
                    },
                    Err(error) => ContextPreparation::Failed {
                        error,
                        mutations: vec![],
                    },
                }
            }
            Err(error) => {
                let receipt = match pl_model::runtime::model_failure_receipt(&error) {
                    Ok(receipt) => receipt,
                    Err(error) => {
                        return ContextPreparation::Failed {
                            error,
                            mutations: vec![],
                        };
                    }
                }
                .map(|receipt| CompactionReceipt {
                    inference_id: id.clone(),
                    binding: receipt.binding,
                    reasoning_effort: reasoning_effort.clone(),
                    requested_service_tier: Some("notApplicable".into()),
                    reasoning_effort_source: Some(if handoff.is_some() {
                        CompactionEffortSource::CurrentModelDefault
                    } else {
                        CompactionEffortSource::FrozenRoute
                    }),
                    context_window,
                    turn_id: turn_id.clone(),
                    accounting: receipt.accounting,
                    model_observation: receipt.model_observation,
                    timing: receipt.timing,
                    implementation: None,
                    error: Some(receipt.message),
                    retained_through_record_id: None,
                    context_summary: previous_summary,
                });
                match receipt {
                    Some(receipt) => failure_with_receipt(error, previous, receipt),
                    None => ContextPreparation::Failed {
                        error,
                        mutations: vec![],
                    },
                }
            }
        }
    }
}

impl StudioCompaction {
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

fn append_preview_facts(
    records: &mut Vec<pl_core::context::ContextRecord>,
    facts: &[pl_core::thread::RuntimeFact],
    sequence: u64,
) {
    use pl_core::context::{ContextRecord, ContextSource};
    for fact in facts {
        let source = ContextSource::RuntimeFact {
            source_id: fact.source_id.clone(),
        };
        if !records
            .iter()
            .rev()
            .find(|record| record.source == source)
            .is_some_and(|record| record.content == fact.content)
        {
            records.push(ContextRecord {
                id: format!("preview:{sequence}:{}", fact.source_id),
                turn_id: None,
                source,
                content: fact.content.clone(),
                tool_calls: vec![],
            });
        }
    }
}

fn failure_with_receipt(
    error: pl_core::model::ModelError,
    previous: Option<u64>,
    receipt: CompactionReceipt,
) -> ContextPreparation {
    match receipt_mutation(previous, receipt) {
        Ok(mutation) => ContextPreparation::Failed {
            error,
            mutations: vec![mutation],
        },
        Err(error) => ContextPreparation::Failed {
            error,
            mutations: vec![],
        },
    }
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

/// Rewind and old checkpoints may carry obsolete instructions. The current extension is the
/// host authority; normalize obsolete text or route bindings without rescanning files.
#[derive(Default)]
struct InstructionRepair {
    binding: Option<InstructionRevisionBinding>,
    replacement: Option<pl_core::thread::ReplaceContext>,
    mutations: Vec<ExtensionMutation>,
}
#[derive(Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct InstructionBinding {
    pub(crate) route_identity: String,
    pub(crate) append_snapshots: bool,
}

pub(crate) fn instruction_binding(
    route: &ResolvedModelRoute,
    model: &ThreadModel,
) -> InstructionBinding {
    InstructionBinding {
        route_identity: model.route_identity(),
        append_snapshots: route.endpoint.instruction_update_strategy(&route.model)
            == pl_model::protocol::InstructionUpdateStrategy::AppendFullSnapshot,
    }
}

pub(crate) fn decode_instruction_binding(
    record: &ExtensionRecord,
) -> std::io::Result<InstructionBinding> {
    if record.payload.format() != "pl.studio.instruction-binding"
        || record.payload.version() != 1
        || record.revision == 0
    {
        return Err(std::io::Error::other("invalid instruction route binding"));
    }
    let binding: InstructionBinding =
        serde_json::from_str(record.payload.content()).map_err(std::io::Error::other)?;
    if binding.route_identity.is_empty() {
        return Err(std::io::Error::other("empty instruction route binding"));
    }
    Ok(binding)
}
fn restore_current_instructions(
    request: &mut ContextPreparationRequest,
    base_instructions: &str,
    binding: &InstructionBinding,
    mode: Option<&crate::mode::RegisteredThreadMode>,
    mut mutations: Vec<ExtensionMutation>,
) -> Result<InstructionRepair, pl_core::model::ModelError> {
    use pl_core::context::{ContextContent, ContextRecord, ContextSource};
    let Some(mut record) = request
        .extensions
        .get(crate::instruction::INSTRUCTIONS_EXTENSION)
        .cloned()
    else {
        return Ok(InstructionRepair {
            mutations,
            ..Default::default()
        });
    };
    if record.revision == 0 {
        return Err(receipt_error(std::io::Error::other(
            "invalid current instruction snapshot authority",
        )));
    }
    // Only the Mode-owned instruction source is refreshed here. The frozen Agent definition and
    // its identity stay untouched, so context preparation can never rewrite the session's role.
    let mut snapshot =
        crate::instruction::decode_snapshot(&record.payload).map_err(receipt_error)?;
    let profile_changed = match mode {
        Some(mode) => snapshot
            .set_mode_instruction(&mode.descriptor().display_name, mode.prompt())
            .map_err(receipt_error)?,
        None => false,
    };
    let previous_binding = request.extensions.get("studio.instructions.binding");
    let binding_changed = previous_binding
        .map(decode_instruction_binding)
        .transpose()
        .map_err(receipt_error)?
        .is_none_or(|previous| previous != *binding);
    if binding_changed {
        mutations.push(ExtensionMutation::Put {
            id: "studio.instructions.binding".into(),
            expected_revision: previous_binding.map(|record| record.revision),
            payload: pl_core::context::OpaquePayload::new(
                "pl.studio.instruction-binding",
                1,
                serde_json::to_string(binding).map_err(receipt_error)?,
            )
            .map_err(receipt_error)?,
        });
    }
    let changed_instruction = snapshot.rebind_model_base(base_instructions) | profile_changed;
    if changed_instruction {
        let expected_revision = record.revision;
        record.payload = crate::instruction::encode_snapshot(&snapshot).map_err(receipt_error)?;
        mutations.push(ExtensionMutation::Put {
            id: crate::instruction::INSTRUCTIONS_EXTENSION.into(),
            expected_revision: Some(expected_revision),
            payload: record.payload.clone(),
        });
        std::sync::Arc::make_mut(&mut request.extensions).insert(
            crate::instruction::INSTRUCTIONS_EXTENSION.into(),
            record.clone(),
        );
    }
    let complete = snapshot.trusted_text();
    let hash = snapshot.trusted_content_hash();
    let current =
        crate::instruction::current_instruction_context(&request.committed_context.records);
    let latest = current.latest_snapshot();
    if current.is_canonical_for(&complete) && (!binding_changed || latest.is_none()) {
        return Ok(InstructionRepair {
            binding: None,
            replacement: None,
            mutations,
        });
    }
    let replaces = latest.and_then(|record| match &record.source {
        ContextSource::InstructionSnapshot {
            content_hash,
            replaces,
            ..
        } => {
            if current.body() == complete {
                replaces.clone()
            } else {
                Some(content_hash.clone())
            }
        }
        _ => None,
    });
    let record_id = format!(
        "instruction:{}:{}",
        request.model.thread_id,
        uuid::Uuid::new_v4()
    );
    let instruction_binding = Some(InstructionRevisionBinding {
        record_id: record_id.clone(),
        extension_id: crate::instruction::INSTRUCTIONS_EXTENSION.into(),
    });
    let canonical = ContextRecord {
        id: record_id,
        turn_id: None,
        source: ContextSource::InstructionSnapshot {
            revision: record.revision,
            content_hash: hash,
            replaces,
        },
        content: vec![ContextContent::Text {
            text: complete.into(),
        }],
        tool_calls: Vec::new(),
    };
    let normalize = |records: &[ContextRecord]| {
        if binding.append_snapshots && !binding_changed {
            let mut next = records.to_vec();
            next.push(canonical.clone());
            return next;
        }
        std::iter::once(canonical.clone())
            .chain(
                records
                    .iter()
                    .filter(|record| {
                        !matches!(
                            record.source,
                            ContextSource::Instruction | ContextSource::InstructionSnapshot { .. }
                        )
                    })
                    .cloned(),
            )
            .collect::<Vec<_>>()
    };
    request.model.context.records = normalize(&request.model.context.records).into();
    // Rebuilding the observed prefix invalidates its measurement even when the record count
    // happens to remain equal. The model validates any remaining candidate against final input.
    request.previous_usage = None;
    let records = normalize(&request.committed_context.records);
    request.committed_context.records = records.clone().into();
    Ok(InstructionRepair {
        binding: instruction_binding,
        replacement: Some(pl_core::thread::ReplaceContext {
            expected_revision: request.committed_context.revision,
            reason: pl_core::thread::ContextReplacementReason::Rebuild,
            records,
        }),
        mutations,
    })
}

/// Capture once at initiating root input admission. Repeated preparation, retries and all tools
/// consume the same self-contained snapshot even when the catalog changes during the Turn.
struct ModePreparation {
    mode: Option<std::sync::Arc<crate::mode::RegisteredThreadMode>>,
    mutations: Vec<ExtensionMutation>,
    new_turn: bool,
}

fn freeze_mode_for_turn(
    request: &mut ContextPreparationRequest,
    modes: &crate::mode::ThreadModeManager,
) -> Result<ModePreparation, pl_core::model::ModelError> {
    if request
        .extensions
        .contains_key(crate::studio::model_route::AGENT_PROFILE_EXTENSION)
    {
        return Ok(ModePreparation {
            mode: None,
            mutations: Vec::new(),
            new_turn: false,
        });
    }
    let record = request
        .extensions
        .get(crate::mode::MODE_EXTENSION)
        .ok_or_else(|| {
            receipt_error(std::io::Error::other(
                "root Thread has no saved Mode snapshot",
            ))
        })?;
    let previous = crate::mode::decode_mode_snapshot(&record.payload).map_err(receipt_error)?;
    let root_prompt = request
        .turn_input
        .as_ref()
        .filter(|input| input.payload.format() == "pl.studio.prompt");
    if root_prompt.is_some_and(|input| input.payload.version() != 1) {
        return Err(receipt_error(std::io::Error::other(
            "unsupported root prompt payload",
        )));
    }
    let new_turn = root_prompt.is_some()
        && previous.frozen_turn_id.as_deref() != Some(request.model.turn_id.as_str());
    let next = if new_turn {
        let mode = modes
            .snapshot()
            .mode(&previous.definition.id)
            .unwrap_or(previous.registered().map_err(receipt_error)?);
        previous
            .updated_for_turn(&mode, request.model.turn_id.clone())
            .map_err(receipt_error)?
    } else {
        previous
    };
    let mode = next.registered().map_err(receipt_error)?;
    let payload = crate::mode::encode_mode_snapshot(&next).map_err(receipt_error)?;
    if record.payload == payload {
        return Ok(ModePreparation {
            mode: Some(mode),
            mutations: Vec::new(),
            new_turn,
        });
    }
    let expected_revision = record.revision;
    std::sync::Arc::make_mut(&mut request.extensions).insert(
        crate::mode::MODE_EXTENSION.into(),
        pl_core::thread::extensions::ExtensionRecord {
            revision: expected_revision,
            payload: payload.clone(),
        },
    );
    Ok(ModePreparation {
        mode: Some(mode),
        mutations: vec![ExtensionMutation::Put {
            id: crate::mode::MODE_EXTENSION.into(),
            expected_revision: Some(expected_revision),
            payload,
        }],
        new_turn,
    })
}

/// Start only from a pending root prompt, or repair an already active graph during execution.
/// The local preview feeds projection; core commits its mutation and facts together by CAS.
fn prepare_workflow(
    request: &mut ContextPreparationRequest,
    new_turn: bool,
) -> Result<Option<ExtensionMutation>, pl_core::model::ModelError> {
    if !new_turn {
        return Ok(None);
    }
    if request
        .extensions
        .contains_key(crate::studio::model_route::AGENT_PROFILE_EXTENSION)
    {
        return Ok(None);
    }
    let mode_record = request
        .extensions
        .get(crate::mode::MODE_EXTENSION)
        .ok_or_else(|| receipt_error(std::io::Error::other("root Thread has no saved Mode")))?;
    let saved = crate::mode::decode_mode_snapshot(&mode_record.payload).map_err(receipt_error)?;
    let mode_id = saved.definition.id.clone();
    let mode = saved.registered().map_err(receipt_error)?;
    let root_prompt = request
        .turn_input
        .as_ref()
        .filter(|input| input.payload.format() == "pl.studio.prompt");
    if root_prompt.is_some_and(|input| input.payload.version() != 1) {
        return Err(receipt_error(std::io::Error::other(
            "unsupported root prompt payload",
        )));
    }
    let record = request
        .extensions
        .get(crate::workflow_tool::WORKFLOW_EXTENSION);
    let state = record
        .map(|record| crate::workflow_tool::decode_workflow_state(&record.payload))
        .transpose()
        .map_err(receipt_error)?;
    let run = state.as_ref().and_then(|state| state.current_run.as_ref());
    if root_prompt.is_none()
        && run
            .is_none_or(|run| run.lifecycle == crate::workflow_tool::WorkflowRunLifecycle::Terminal)
    {
        return Ok(None);
    }
    if run.is_some_and(|run| {
        run.mode_id == mode_id
            && run.lifecycle == crate::workflow_tool::WorkflowRunLifecycle::Active
            && mode
                .workflow()
                .is_some_and(|graph| run.graph_hash == graph.graph_hash())
    }) {
        return Ok(None);
    }
    let expected_revision = record.map(|record| record.revision);
    let Some(state) = crate::workflow_tool::reconcile_workflow_for_turn(
        state,
        &mode.descriptor().id,
        mode.workflow_binding(),
        &request.model.thread_id,
        crate::studio::unix_seconds(),
    )
    .map_err(receipt_error)?
    else {
        return Ok(None);
    };
    let payload = crate::workflow_tool::encode_workflow_state(&state).map_err(receipt_error)?;
    if record.is_some_and(|record| record.payload == payload) {
        return Ok(None);
    }
    std::sync::Arc::make_mut(&mut request.extensions).insert(
        crate::workflow_tool::WORKFLOW_EXTENSION.into(),
        pl_core::thread::extensions::ExtensionRecord {
            revision: expected_revision.unwrap_or(0),
            payload: payload.clone(),
        },
    );
    Ok(Some(ExtensionMutation::Put {
        id: crate::workflow_tool::WORKFLOW_EXTENSION.into(),
        expected_revision,
        payload,
    }))
}

/// Each projection consumes only this Thread's frozen extensions, never a parent's state.
fn current_facts(
    request: &ContextPreparationRequest,
) -> Result<Vec<pl_core::thread::RuntimeFact>, pl_core::model::ModelError> {
    use pl_core::{context::ContextContent, thread::RuntimeFact};
    let mut facts = request
        .current_facts
        .iter()
        .filter(|fact| {
            !matches!(
                fact.source_id.as_str(),
                "studio.plan" | "studio.plan.document" | "studio.workflow" | "studio.workspace"
            ) && !fact.source_id.starts_with("studio.instructions:")
        })
        .cloned()
        .map(|fact| (fact.source_id.clone(), fact))
        .collect::<std::collections::BTreeMap<_, _>>();
    let mut put = |source_id: &str, content: String| {
        facts.insert(
            source_id.into(),
            RuntimeFact {
                source_id: source_id.into(),
                content: vec![ContextContent::Text {
                    text: content.into(),
                }],
            },
        );
    };
    if let Some(record) = request.extensions.get(crate::plan_tool::PLAN_EXTENSION) {
        let state = crate::plan_tool::decode_plan_state(&record.payload).map_err(receipt_error)?;
        let section =
            crate::plan_tool::plan_model_context_section(&state).map_err(receipt_error)?;
        let mut metadata: serde_json::Value =
            serde_json::from_str(&section.content).map_err(receipt_error)?;
        if let Some(document) = &state.plan.document {
            put("studio.plan.document", serde_json::to_string(&serde_json::json!({"version":document.revision,"contentHash":document.hash,"markdown":document.content})).map_err(receipt_error)?);
            if let Some(document) = metadata
                .get_mut("document")
                .and_then(serde_json::Value::as_object_mut)
            {
                document.remove("markdown");
            }
        } else {
            put(
                "studio.plan.document",
                "Previous plan document is no longer current.".into(),
            );
        }
        put(
            "studio.plan",
            serde_json::to_string(&metadata).map_err(receipt_error)?,
        );
    }
    if let Some(record) = request
        .extensions
        .get(crate::workflow_tool::WORKFLOW_EXTENSION)
    {
        let state =
            crate::workflow_tool::decode_workflow_state(&record.payload).map_err(receipt_error)?;
        if state.current_run.is_some() {
            let saved = request
                .extensions
                .get(crate::mode::MODE_EXTENSION)
                .ok_or_else(|| {
                    receipt_error(std::io::Error::other(
                        "current workflow Mode snapshot is unavailable",
                    ))
                })?;
            let mode = crate::mode::decode_mode_snapshot(&saved.payload)
                .and_then(|mode| mode.registered())
                .map_err(receipt_error)?;
            let section = crate::workflow_tool::workflow_model_context_section(
                &state,
                mode.workflow_binding(),
            )
            .map_err(receipt_error)?
            .ok_or_else(|| {
                receipt_error(std::io::Error::other(
                    "current workflow state does not match its registered graph",
                ))
            })?;
            put("studio.workflow", section.content);
        }
    }
    if let Some(record) = request.extensions.get("studio.workspace") {
        put(
            "studio.workspace",
            format!("Assigned workspace:\n{}", record.payload.content()),
        );
    }
    if let Some(record) = request
        .extensions
        .get(crate::instruction::INSTRUCTIONS_EXTENSION)
    {
        let snapshot =
            crate::instruction::decode_snapshot(&record.payload).map_err(receipt_error)?;
        for record in snapshot.context_records(&request.model.thread_id) {
            if let pl_core::context::ContextSource::RuntimeFact { source_id } = record.source {
                facts.insert(
                    source_id.clone(),
                    RuntimeFact {
                        source_id,
                        content: record.content,
                    },
                );
            }
        }
    }
    Ok(facts.into_values().collect())
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
fn receipt_error(
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

/// Producer payload conversion is confined to the persisted checkpoint migration boundary.
pub(crate) fn migrate_checkpoint_sources(
    checkpoint: &mut pl_core::thread::ThreadCheckpoint,
) -> anyhow::Result<()> {
    use pl_core::context::ContextSource;
    for record in std::sync::Arc::make_mut(&mut checkpoint.state.context.records) {
        if let ContextSource::Runtime { source_id } = &record.source
            && ((source_id == "studio.workspace"
                && record.id == format!("workspace:{}", checkpoint.thread_id))
                || (source_id == "studio.workflow"
                    && record.id == format!("workflow:{}:initial", checkpoint.thread_id)))
        {
            record.source = ContextSource::RuntimeFact {
                source_id: source_id.clone(),
            };
        }
    }
    let Some(record) = checkpoint.state.extensions.get(LATEST_RECEIPT) else {
        return Ok(());
    };
    if record.payload.format() != "pl.studio.compaction" || record.payload.version() != 1 {
        return Ok(());
    }
    let receipt = crate::studio::producer_migration::compaction_receipt(
        record.payload.version(),
        record.payload.content(),
    )?;
    if receipt.error.is_some() || receipt.implementation.as_deref() != Some("native") {
        return Ok(());
    }
    for record in std::sync::Arc::make_mut(&mut checkpoint.state.context.records) {
        pl_model::runtime::migrate_legacy_compaction(
            record,
            &receipt.inference_id,
            receipt.binding.clone(),
        )?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    //! A source-side handoff below the target's automatic compaction threshold.
    use super::*;
    use anyhow::{Context, Result};
    use pl_core::{
        context::{ContextContent, ContextSnapshot},
        model::{ModelFactory, ModelRequest, ToolCallMode},
        thread::{
            ContextReplacementReason, ModelStepLimit, ReplaceContext, ThreadHandle, TurnInput,
            extensions::ExtensionMutation,
        },
    };
    use pl_model::{
        config::{AccountConfig, AccountId, ModelRouteConfig},
        model::{ModelDefinition, ModelTransportProfile},
    };
    use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
    use serde_json::json;

    fn turn(id: &str, text: &str) -> TurnInput {
        TurnInput {
            turn_id: id.into(),
            attempt_prefix: id.into(),
            content: vec![ContextContent::Text { text: text.into() }],
            max_model_steps: ModelStepLimit::Limited(2.try_into().unwrap()),
            cancellation: Default::default(),
        }
    }

    #[tokio::test]
    async fn switches_to_a_larger_model_and_reuses_handoff_after_target_failure() -> Result<()> {
        let ledger = "prior ledger marker";
        let mut reported = responses_text("source answer", "source-turn", "source");
        reported.last_mut().unwrap()["response"]["usage"]["input_tokens"] = json!(37);
        let options = policy(OpenAiCompactionMode::Local);
        let source = FixtureServer::start(vec![
            Step::prompt(Protocol::ResponsesHttp, ledger, 0, Reply::Sse(reported)),
            Step::prompt(
                Protocol::ResponsesHttp,
                format!("{}\n\n{}", options.instructions, options.requirement),
                1,
                Reply::Sse(responses_text(
                    "source handoff summary",
                    "summary",
                    "source",
                )),
            ),
        ])
        .await?;
        let target = FixtureServer::start(vec![
            Step::prompt(
                Protocol::ResponsesHttp,
                "TARGET_PENDING_INPUT_ONLY",
                0,
                Reply::HttpError {
                    status: 400,
                    code: "invalid_request_error".into(),
                    message: "fixture target error".into(),
                },
            ),
            Step::prompt(
                Protocol::ResponsesHttp,
                "TARGET_RETRY",
                1,
                Reply::Sse(responses_text("target continued", "target-turn", "target")),
            ),
        ])
        .await?;
        let mut config = crate::StudioConfig::default_config()?;
        config.models.accounts.clear();
        for (id, endpoint, window, threshold, base) in [
            ("source", source.base_url(), 272_000, 244_800, "SOURCE_BASE"),
            (
                "target",
                target.base_url(),
                1_000_000,
                900_000,
                "TARGET_BASE",
            ),
        ] {
            let mut model = ModelDefinition::compatible(id);
            model
                .extra
                .binding
                .set_transport(ModelTransportProfile::responses_http());
            model.base.context_window = Some(window);
            model.base.max_context_window = Some(window);
            model.extra.max_output_tokens = Some(1024);
            model.base.auto_compact_token_limit = Some(threshold);
            model.base.model_messages.instructions_template = base.into();
            config.models.accounts.insert(
                AccountId::new(id)?,
                AccountConfig::from_explicit_models(
                    pl_model::protocol::providers::openai::compatible_endpoint(id, endpoint),
                    vec![model],
                ),
            );
        }
        let resolve = |id: &str| {
            config.models.resolve_route(
                crate::config::root_agent_route_id(),
                &ModelRouteConfig {
                    account_id: AccountId::new(id).unwrap(),
                    model_id: id.into(),
                    effort: None,
                },
            )
        };
        let source_route = resolve("source")?;
        let target_route = resolve("target")?;
        let source_model = ThreadModel::new(pl_model::runtime::from_route(&source_route)?, None);
        let modes = crate::mode::ThreadModeManager::default();
        let registry = crate::studio::thread::register_builtins(&modes)?;
        let mode = registry
            .mode(&crate::mode::ThreadModeId::auto())
            .context("Auto mode")?;
        let snapshot: crate::instruction::InstructionSnapshot = serde_json::from_value(json!({
            "agent": {"id":"root:main", "scope":"root", "usageBinding":{"kind":"rootEntry","entry":"studio"},
                "revision":"1", "origin":"builtin"},
            "agentShape":{"state":"present","contentHash":pl_core::context::content_hash(b"fixture root instruction")},
            "base":{"source":{"kind":"modelBase","label":"model base"},"content":"SOURCE_BASE"},
            "developer":[
                {"source":{"kind":"agentDefinition","label":"fixture root"},"content":"fixture root instruction"},
                {"source":{"kind":"modeDefinition","label":mode.descriptor().display_name},"content":mode.prompt()}
            ], "user":[]
        }))?;
        let thread = ThreadHandle::start(
            "usage-handoff".into(),
            ModelFactory::new(source_model.clone())
                .open_session()
                .await?,
        )?;
        thread
            .replace_context(ReplaceContext {
                expected_revision: 0,
                reason: ContextReplacementReason::Rebuild,
                records: snapshot.context_records("usage-handoff"),
            })
            .await?;
        thread
            .mutate_extensions(vec![
                ExtensionMutation::Put {
                    id: crate::mode::MODE_EXTENSION.into(),
                    expected_revision: None,
                    payload: crate::mode::encode_mode_snapshot(
                        &crate::mode::SavedThreadMode::capture(&mode, None),
                    )?,
                },
                ExtensionMutation::Put {
                    id: crate::instruction::INSTRUCTIONS_EXTENSION.into(),
                    expected_revision: None,
                    payload: crate::instruction::encode_snapshot(&snapshot)?,
                },
                ExtensionMutation::Put {
                    id: "studio.instructions.binding".into(),
                    expected_revision: None,
                    payload: pl_core::context::OpaquePayload::new(
                        "pl.studio.instruction-binding",
                        1,
                        serde_json::to_string(&instruction_binding(&source_route, &source_model))?,
                    )?,
                },
            ])
            .await?;
        thread.run_turn(turn("source-turn", ledger)).await?;
        let before = thread.snapshot();
        let origin = before
            .last_attempt_usage_origin
            .as_ref()
            .context("source observation")?;
        assert_eq!(origin.context_revision, before.context.revision);
        assert_eq!(
            before.last_attempt_usage.as_ref().unwrap().input_tokens,
            Some(37)
        );
        let target_model = ThreadModel::new(pl_model::runtime::from_route(&target_route)?, None);
        let mut preview = before.context.records.to_vec();
        preview.push(pl_core::context::ContextRecord {
            id: "target-input".into(),
            turn_id: Some("target-turn".into()),
            source: pl_core::context::ContextSource::User,
            content: vec![ContextContent::Text {
                text: "TARGET_PENDING_INPUT_ONLY".into(),
            }],
            tool_calls: vec![],
        });
        let request = ModelRequest {
            thread_id: "usage-handoff".into(),
            turn_id: "target-turn".into(),
            attempt_id: "target-turn:0".into(),
            context: ContextSnapshot {
                revision: before.context.revision,
                records: preview.into(),
            },
            tools: Default::default(),
            tool_call_mode: ToolCallMode::Parallel,
            solo_tool_ids: Default::default(),
            committed_private_context: None,
            resources: None,
            cancellation: Default::default(),
            progress: None,
            members: None,
        };
        let estimate = target_model
            .estimate_input(&request, None)
            .await?
            .context("rough text estimate")?;
        assert!(estimate.tokens < target_route.context.auto_compact_limit.unwrap());
        assert_eq!(
            target_model
                .compaction_decision(&request, None, false)
                .await?,
            pl_model::runtime::ThreadCompactionDecision::Keep
        );
        let model = crate::studio::model_binding::deferred_update(&target_route, &config, modes)?;
        let update = pl_core::thread::RuntimeBundle::model_only(&thread, &thread.snapshot(), model);
        thread
            .install_runtime_bundle(update)
            .await?
            .installed()
            .await?;
        let failed = thread
            .run_turn(turn("target-turn", "TARGET_PENDING_INPUT_ONLY"))
            .await
            .expect_err("the target rejects its first request");
        assert!(matches!(failed, pl_core::thread::ThreadError::Model(_)));
        assert!(failed.to_string().contains("fixture target error"));
        thread.run_turn(turn("retry-turn", "TARGET_RETRY")).await?;
        let after = thread.snapshot();
        let saved = after
            .extensions
            .get(LATEST_RECEIPT)
            .context("source summary must precede target continuation")?;
        let receipt = decode_receipt(saved.payload.version(), saved.payload.content())?;
        assert_eq!(receipt.binding.account_id, "source");
        assert_eq!(receipt.accounting.usage.input_tokens, Some(11));
        assert!(receipt.context_summary.context("summary origin")?.portable);
        assert_eq!(
            after.last_attempt_usage.as_ref().unwrap().input_tokens,
            Some(11),
            "source usage is not target usage"
        );
        thread.close().await?;
        let source_requests = source.finish().await?;
        assert_eq!(source_requests.len(), 2);
        let summary = source_requests[1].body.to_string();
        assert!(summary.contains("SOURCE_BASE") && summary.contains(ledger));
        assert!(!summary.contains("TARGET_BASE") && !summary.contains("TARGET_PENDING_INPUT_ONLY"));
        let target_requests = target.finish().await?;
        assert_eq!(target_requests.len(), 2);
        for request in target_requests {
            let continuation = request.body.to_string();
            assert!(continuation.contains("source handoff summary"));
            assert!(continuation.contains("TARGET_BASE"));
            assert!(!continuation.contains(ledger));
        }
        Ok(())
    }
}

#[cfg(test)]
#[path = "compaction_instruction_normalization_tests.rs"]
mod instruction_normalization_tests;

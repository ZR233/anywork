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
    extensions::ExtensionMutation,
};
use pl_model::{
    config::ResolvedModelRoute,
    runtime::{ModelRuntime, ThreadModel},
};

/// Binds the policy to the same frozen route as the main model session.
pub(crate) fn preparer(
    route: &ResolvedModelRoute,
    mode: OpenAiCompactionMode,
    modes: crate::mode::ThreadModeManager,
) -> Result<Option<ContextPreparer>, pl_model::PureError> {
    let model = ThreadModel::new(ModelRuntime::from_route(route)?, route.reasoning_config());
    let instruction_binding = InstructionBinding {
        route_identity: model.route_identity(),
        append_snapshots: route.endpoint.instruction_update_strategy(&route.model)
            == pl_model::protocol::InstructionUpdateStrategy::AppendFullSnapshot,
    };
    Ok(Some(ContextPreparer::new(StudioCompaction {
        model,
        limit: route.auto_compact_limit,
        modes,
        reasoning_effort: route
            .effort
            .as_ref()
            .map(|effort| effort.as_str().to_owned()),
        context_window: route.model.resolved_context_window(),
        options: policy(mode),
        base_instructions: route.model.base_instructions.clone(),
        instruction_binding,
        supports_workflow: route.model.capabilities.supports_function_calling(),
    })))
}

#[derive(Debug)]
struct StudioCompaction {
    model: ThreadModel,
    limit: Option<u64>,
    modes: crate::mode::ThreadModeManager,
    reasoning_effort: Option<String>,
    context_window: Option<u64>,
    options: ThreadCompactionOptions,
    base_instructions: String,
    instruction_binding: InstructionBinding,
    supports_workflow: bool,
}
impl ContextPreparationHook for StudioCompaction {
    async fn before_step(&self, mut request: ContextPreparationRequest) -> ContextPreparation {
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
        let unchanged = || ContextPreparation::Prepared {
            excluded_tool_ids: excluded_tool_ids.clone(),
            expected_extension_sequence: request.extension_sequence,
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
        let limit = match self.limit {
            Some(limit) => limit,
            None if request.force_compaction => u64::MAX,
            None => return unchanged(),
        };
        let mut preview = request.model.clone();
        let mut records = preview.context.records.to_vec();
        // Capacity includes freshly projected state, as well as this step's frozen input.
        for fact in &facts {
            let source = pl_core::context::ContextSource::RuntimeFact {
                source_id: fact.source_id.clone(),
            };
            if !records
                .iter()
                .rev()
                .find(|record| record.source == source)
                .is_some_and(|record| record.content == fact.content)
            {
                records.push(pl_core::context::ContextRecord {
                    id: format!("preview:{}:{}", request.extension_sequence, fact.source_id),
                    turn_id: None,
                    source,
                    content: fact.content.clone(),
                    tool_calls: Vec::new(),
                });
            }
        }
        preview.context.records = records.into();
        let estimate = match self
            .model
            .estimate_input(&preview, request.previous_usage.as_ref())
            .await
        {
            Ok(estimate) => estimate.map(|estimate| estimate.tokens),
            Err(error) => {
                return ContextPreparation::Failed {
                    error,
                    mutations: vec![],
                };
            }
        };
        if request
            .committed_context
            .records
            .iter()
            .all(|record| record.source == pl_core::context::ContextSource::Instruction)
            || (!request.force_compaction && !estimate.is_some_and(|tokens| tokens >= limit))
        {
            return unchanged();
        }
        let turn_id = request.model.turn_id.clone();
        let id = format!(
            "studio.compaction:{}:{}",
            request.model.attempt_id, request.extension_sequence
        );
        let previous = request
            .extensions
            .get(LATEST_RECEIPT)
            .map(|record| record.revision);
        let mut model_request = request.model;
        model_request.context = request.committed_context;
        model_request.attempt_id = id.clone();
        match self
            .model
            .compact(model_request, self.options.clone())
            .await
        {
            Ok(result) => {
                let receipt = CompactionReceipt {
                    inference_id: id.clone(),
                    binding: result.binding,
                    reasoning_effort: self.reasoning_effort.clone(),
                    context_window: self.context_window,
                    turn_id: turn_id.clone(),
                    accounting: result.accounting,
                    model_observation: result.model_observation,
                    implementation: Some(
                        match result.implementation {
                            ThreadCompactionStrategy::TextSummary => "textSummary",
                            ThreadCompactionStrategy::PreferNative => "native",
                        }
                        .into(),
                    ),
                    error: None,
                };
                let mut rejected = receipt.clone();
                rejected.error =
                    Some("context preparation candidate was cancelled or rejected".into());
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
                        expected_extension_sequence: request.extension_sequence,
                        rejected_mutations,
                        replacement: Some(result.replacement),
                        facts,
                        mutations: instruction_repair
                            .mutations
                            .clone()
                            .into_iter()
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
                let receipt = pl_model::runtime::model_failure_receipt(&error)
                    .ok()
                    .flatten()
                    .map(|receipt| CompactionReceipt {
                        inference_id: id.clone(),
                        binding: receipt.binding,
                        reasoning_effort: self.reasoning_effort.clone(),
                        context_window: self.context_window,
                        turn_id: turn_id.clone(),
                        accounting: receipt.accounting,
                        model_observation: receipt.model_observation,
                        implementation: None,
                        error: Some(receipt.message),
                    });
                let mutations = receipt
                    .and_then(|receipt| receipt_mutation(previous, receipt).ok())
                    .into_iter()
                    .collect();
                ContextPreparation::Failed { error, mutations }
            }
        }
    }
}

/// Rewind and old checkpoints may carry obsolete instructions. The current extension is the
/// host authority; normalize obsolete text or route bindings without rescanning files.
#[derive(Default)]
struct InstructionRepair {
    replacement: Option<pl_core::thread::ReplaceContext>,
    mutations: Vec<ExtensionMutation>,
}
#[derive(Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct InstructionBinding {
    route_identity: String,
    append_snapshots: bool,
}
fn restore_current_instructions(
    request: &mut ContextPreparationRequest,
    base_instructions: &str,
    binding: &InstructionBinding,
    mode: Option<&crate::mode::RegisteredThreadMode>,
    mut mutations: Vec<ExtensionMutation>,
) -> Result<InstructionRepair, pl_core::model::ModelError> {
    use pl_core::context::{ContextContent, ContextRecord, ContextSource};
    let Some(mut record) = request.extensions.get("studio.instructions").cloned() else {
        return Ok(InstructionRepair::default());
    };
    if record.payload.format() != "pl.studio.instructions"
        || record.payload.version() != 1
        || record.revision == 0
    {
        return Err(receipt_error(std::io::Error::other(
            "invalid current instruction snapshot authority",
        )));
    }
    let mut snapshot: crate::instruction::InstructionSnapshot =
        serde_json::from_str(record.payload.content()).map_err(receipt_error)?;
    let profile_changed = if let Some(mode) = mode {
        let profile = snapshot
            .developer
            .iter_mut()
            .find(|block| {
                block.source.kind == crate::instruction::InstructionSourceKind::ExecutionProfile
            })
            .ok_or_else(|| {
                receipt_error(std::io::Error::other(
                    "saved instructions contain no Mode profile",
                ))
            })?;
        let changed = profile.content != mode.prompt()
            || profile.source.label != mode.descriptor().display_name;
        profile.content = mode.prompt().to_owned();
        profile
            .source
            .label
            .clone_from(&mode.descriptor().display_name);
        changed
    } else {
        false
    };
    let previous_binding = request.extensions.get("studio.instructions.binding");
    let binding_changed = match previous_binding {
        Some(record) => {
            if record.payload.format() != "pl.studio.instruction-binding"
                || record.payload.version() != 1
                || record.revision == 0
            {
                return Err(receipt_error(std::io::Error::other(
                    "invalid instruction route binding",
                )));
            }
            let previous: InstructionBinding =
                serde_json::from_str(record.payload.content()).map_err(receipt_error)?;
            if previous.route_identity.is_empty() {
                return Err(receipt_error(std::io::Error::other(
                    "empty instruction route binding",
                )));
            }
            previous != *binding
        }
        None => true,
    };
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
    if snapshot.rebind_model_base(base_instructions) | profile_changed {
        let expected_revision = record.revision;
        record.revision = request
            .extension_sequence
            .checked_add(u64::try_from(mutations.len()).map_err(receipt_error)?)
            .and_then(|sequence| sequence.checked_add(1))
            .ok_or_else(|| {
                receipt_error(std::io::Error::other("instruction revision exhausted"))
            })?;
        record.payload = pl_core::context::OpaquePayload::new(
            "pl.studio.instructions",
            1,
            serde_json::to_string(&snapshot).map_err(receipt_error)?,
        )
        .map_err(receipt_error)?;
        mutations.push(ExtensionMutation::Put {
            id: "studio.instructions".into(),
            expected_revision: Some(expected_revision),
            payload: record.payload.clone(),
        });
        std::sync::Arc::make_mut(&mut request.extensions)
            .insert("studio.instructions".into(), record.clone());
    }
    let rendered = snapshot.context_records(&request.model.thread_id);
    let complete = rendered
        .iter()
        .filter(|record| record.source == ContextSource::Instruction)
        .flat_map(|record| &record.content)
        .filter_map(|content| match content {
            ContextContent::Text { text } => Some(text.as_ref()),
            _ => None,
        })
        .collect::<Vec<_>>()
        .join("\n");
    let hash = pl_core::context::content_hash(complete.as_bytes());
    let latest = request
        .committed_context
        .records
        .iter()
        .rev()
        .find(|record| matches!(record.source, ContextSource::InstructionSnapshot { .. }));
    let current = if let Some(record) = latest {
        record
            .content
            .iter()
            .filter_map(|content| match content {
                ContextContent::Text { text } => Some(text.as_ref()),
                _ => None,
            })
            .collect::<Vec<_>>()
            .join("\n")
    } else {
        request
            .committed_context
            .records
            .iter()
            .filter(|record| record.source == ContextSource::Instruction)
            .flat_map(|record| &record.content)
            .filter_map(|content| match content {
                ContextContent::Text { text } => Some(text.as_ref()),
                _ => None,
            })
            .collect::<Vec<_>>()
            .join("\n")
    };
    if current == complete && (!binding_changed || latest.is_none()) {
        return Ok(InstructionRepair {
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
            if current == complete {
                replaces.clone()
            } else {
                Some(content_hash.clone())
            }
        }
        _ => None,
    });
    let canonical = ContextRecord {
        id: format!(
            "instruction:{}:restore:{}",
            request.model.thread_id, record.revision
        ),
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
    // Core validated usage against the frozen pre-repair prefix. Rebuilding it invalidates
    // that proof even if the record count happens to remain equal.
    request.previous_usage = None;
    let records = normalize(&request.committed_context.records);
    request.committed_context.records = records.clone().into();
    Ok(InstructionRepair {
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
    let record = request.extensions.get("studio.mode").ok_or_else(|| {
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
        "studio.mode".into(),
        pl_core::thread::extensions::ExtensionRecord {
            revision: request.extension_sequence.saturating_add(1),
            payload: payload.clone(),
        },
    );
    Ok(ModePreparation {
        mode: Some(mode),
        mutations: vec![ExtensionMutation::Put {
            id: "studio.mode".into(),
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
        .get("studio.mode")
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
        && run.is_none_or(|run| run.lifecycle == pl_protocol::WorkflowRunLifecycle::Terminal)
    {
        return Ok(None);
    }
    if run.is_some_and(|run| {
        run.mode_id == mode_id
            && run.lifecycle == pl_protocol::WorkflowRunLifecycle::Active
            && mode
                .workflow()
                .is_some_and(|graph| run.graph_hash == graph.graph_hash())
    }) {
        return Ok(None);
    }
    let expected_revision = record.map(|record| record.revision);
    let Some(state) = crate::mode::reconcile_workflow_for_turn(
        state,
        &mode,
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
        if let Some(document) = &state.document {
            put("studio.plan.document", serde_json::to_string(&serde_json::json!({"version":document.version,"contentHash":document.content_hash,"markdown":document.markdown})).map_err(receipt_error)?);
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
            let saved = request.extensions.get("studio.mode").ok_or_else(|| {
                receipt_error(std::io::Error::other(
                    "current workflow Mode snapshot is unavailable",
                ))
            })?;
            let mode = crate::mode::decode_mode_snapshot(&saved.payload)
                .and_then(|mode| mode.registered())
                .map_err(receipt_error)?;
            let section =
                crate::mode::workflow_model_context_section(&state, &mode).ok_or_else(|| {
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
    if let Some(record) = request.extensions.get("studio.instructions") {
        let snapshot: crate::instruction::InstructionSnapshot =
            serde_json::from_str(record.payload.content()).map_err(receipt_error)?;
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

/// Auxiliary model accounting is retained separately from normal turn-response receipts.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct CompactionReceipt {
    pub inference_id: String,
    pub binding: pl_model::runtime::ModelCallBinding,
    pub reasoning_effort: Option<String>,
    pub context_window: Option<u64>,
    pub turn_id: String,
    pub accounting: pl_model::completion::InferenceAccounting,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model_observation: Option<pl_protocol::InferenceModelObservation>,
    pub implementation: Option<String>,
    pub error: Option<String>,
}
fn receipt_mutation(
    expected_revision: Option<u64>,
    receipt: CompactionReceipt,
) -> Result<ExtensionMutation, pl_core::model::ModelError> {
    let payload = serde_json::to_string(&receipt).map_err(receipt_error)?;
    let payload = pl_core::context::OpaquePayload::new("pl.studio.compaction", 2, payload)
        .map_err(receipt_error)?;
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

/// 版本化压缩回执的唯一边界解码。
///
/// v1 载荷的 `binding` 是 Provider/Preset 时代的 camelCase 接入身份
/// （`providerInstanceId`/`requestedModel`/`adapter`/`protocol`）。迁移与产品投影都必须共用这一
/// 处转换，才能在不猜账号/模型的前提下把旧冻结事实并入当前账号、配置模型与厂商协议语义。
/// 只改本 crate 自己写入的已知键；`accounting`、`inferenceId`、`purpose`、`isolation`、观察与
/// 用量等冻结事实原样保留，不改写 opaque 正文。
pub(crate) fn decode_receipt(version: u32, content: &str) -> anyhow::Result<CompactionReceipt> {
    anyhow::ensure!(
        (1..=2).contains(&version),
        "unsupported auxiliary accounting receipt"
    );
    let mut value: serde_json::Value = serde_json::from_str(content)?;
    if version < 2 {
        let receipt = value
            .as_object_mut()
            .ok_or_else(|| anyhow::anyhow!("compaction receipt is not an object"))?;
        if let Some(binding) = receipt
            .get_mut("binding")
            .and_then(serde_json::Value::as_object_mut)
        {
            // 真实 v1 binding 是 camelCase：providerInstanceId/requestedModel/adapter/protocol。
            crate::studio::payload_alias::rename_key(binding, "providerInstanceId", "accountId")?;
            crate::studio::payload_alias::rename_key(binding, "requestedModel", "modelId")?;
            // 旧 `protocol` 是 wire API；旧 `adapter` 才是当前厂商协议选择。
            crate::studio::payload_alias::rename_key(binding, "protocol", "wireApi")?;
            if let Some(adapter) = binding.remove("adapter") {
                let adapter = adapter.as_str().unwrap_or_default();
                let protocol = crate::studio::payload_alias::protocol_from_legacy_adapter(adapter)
                    .ok_or_else(|| {
                        anyhow::anyhow!("unsupported legacy account adapter in compaction receipt")
                    })?;
                binding.insert(
                    "protocol".into(),
                    serde_json::Value::String(protocol.into()),
                );
            }
        }
    }
    serde_json::from_value(value).map_err(anyhow::Error::from)
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
    let receipt = decode_receipt(record.payload.version(), record.payload.content())?;
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

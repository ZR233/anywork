//! Product Mode changes are a single idle core transaction followed by directory projection.
use super::StudioRuntime;
use crate::instruction::INSTRUCTIONS_EXTENSION;
use crate::mode::{MODE_EXTENSION, RegisteredThreadMode, ThreadModeId};
use crate::studio::model_binding::{self, NativeBundleOwner, NativeModelConfiguration};
use anyhow::{Context, Result};
use pl_core::thread::{
    ContextReplacementReason, ReplaceContext, RuntimeApplication, RuntimeFact,
    extensions::{ApplicationUpdate, ExtensionMutation},
};
use pl_core::thread::{RuntimeBundle, ThreadHandle, ThreadSnapshot};

struct ModeCompletion {
    operation_id: String,
    thread_id: String,
    mode_id: ThreadModeId,
    changed_at: i64,
    _lifecycle: tokio::sync::OwnedMutexGuard<()>,
    _installation: tokio::sync::OwnedMutexGuard<()>,
}

impl StudioRuntime {
    pub async fn set_thread_mode(
        &self,
        operation_id: String,
        thread_id: &str,
        mode_id: ThreadModeId,
    ) -> Result<crate::ThreadModeCommandReply> {
        Self::validate_operation_id(&operation_id)?;
        let lifecycle = self.lifecycle_lock.clone().lock_owned().await;
        let record = self.read_owned_thread(thread_id).await?;
        anyhow::ensure!(
            record.parent_thread_id.is_none(),
            "only a root Thread can change mode"
        );
        let mode = self
            .thread_modes
            .snapshot()
            .mode(&mode_id)
            .context("selected Thread Mode is unavailable")?;
        let (config, settings_revision) = self.config_runtime.native_configuration()?;
        let model = config.mode_model_route(&mode_id)?.clone();
        let thread = self.ensure_thread_owner(thread_id).await?;
        let (gate, cancellation) = self.thread_factory.tool_operation(thread_id)?;
        let _installation = tokio::select! {
            biased;
            () = cancellation.cancelled() => return Err(pl_core::thread::ThreadError::Closed.into()),
            guard = gate.lock_owned() => guard,
        };
        let state = thread.snapshot();
        let changed_at = crate::studio::unix_seconds();
        let application =
            prepare_mode_application(thread_id, &state, &mode, &config, model, changed_at)?;
        let prepared = PreparedModeInstallation {
            application,
            settings_revision,
        };
        let update = self
            .prepare_mode_bundle(thread_id, &thread, &state, &mode_id, prepared, cancellation)
            .await?;
        let operation = format!("reconfigure Mode {mode_id} for Thread {thread_id}");
        let completion = ModeCompletion {
            operation_id,
            thread_id: thread_id.to_owned(),
            mode_id,
            changed_at,
            _lifecycle: lifecycle,
            _installation,
        };
        self.install_thread_mode(thread, update, operation, completion)
            .await
    }

    async fn install_thread_mode(
        &self,
        thread: ThreadHandle,
        update: RuntimeBundle,
        operation: String,
        completion: ModeCompletion,
    ) -> Result<crate::ThreadModeCommandReply> {
        let runtime = self.clone();
        let result = self
            .rejected_tools
            .reconfigure(thread, update, operation, move |committed| async move {
                runtime.complete_thread_mode(committed, completion).await
            })
            .await;
        if result.is_err() {
            self.tool_catalog_updates.notify_one();
        }
        result
    }

    async fn prepare_mode_bundle(
        &self,
        thread_id: &str,
        thread: &ThreadHandle,
        state: &ThreadSnapshot,
        mode_id: &ThreadModeId,
        prepared: PreparedModeInstallation,
        cancellation: tokio_util::sync::CancellationToken,
    ) -> Result<RuntimeBundle> {
        let PreparedModeApplication {
            candidate,
            application,
        } = prepared.application;
        let configuration = NativeModelConfiguration::resolve(&self.config_runtime, &candidate)?;
        if self.config_runtime.native_runtime_revision()? != prepared.settings_revision {
            return Err(pl_core::thread::ThreadError::StaleRuntimeBundle.into());
        }
        let desired = format!("mode:{mode_id}:{}", configuration.desired()).into();
        let session = self.require_session(thread_id)?;
        let mut update = configuration
            .prepare_bundle(
                NativeBundleOwner {
                    id: thread_id,
                    session: &session,
                    factory: &self.thread_factory,
                    config: &self.config_runtime,
                    thread,
                    snapshot: &candidate,
                },
                cancellation,
                desired,
                || true,
            )
            .await?;
        update.base = model_binding::bundle_base(thread, state);
        update.model_context_revision = Some(state.context.revision);
        update.base.extension_inputs.include_keys(
            &state.extensions,
            &[
                INSTRUCTIONS_EXTENSION,
                "studio.instructions.binding",
                crate::workflow_tool::WORKFLOW_EXTENSION,
            ],
        );
        update.application = Some(application);
        Ok(update)
    }

    async fn complete_thread_mode(
        &self,
        committed: std::sync::Arc<pl_core::thread::ThreadSnapshot>,
        completion: ModeCompletion,
    ) -> Result<crate::ThreadModeCommandReply> {
        let ModeCompletion {
            operation_id,
            thread_id,
            mode_id,
            changed_at,
            _lifecycle,
            _installation,
        } = completion;
        self.thread_factory.notify_lsp_binding_changed();
        // The projection owner records this committed Mode before awaiting persistence.
        let directory_commit = self
            .agent_facility
            .product_events
            .commit_observed_thread_mode(&thread_id, mode_id, changed_at)
            .await;
        let result = directory_commit
            .context("directory Mode fact is retained by write-behind for persistence retry")
            .and_then(|directory_commit| self.thread_directory_stamp(&directory_commit))
            .map(|directory_stamp| crate::ThreadModeCommandReply {
                receipt: self.command_receipt(
                    operation_id,
                    true,
                    vec![
                        self.resource_stamp(format!("thread-state:{thread_id}"), committed.commit_sequence),
                        directory_stamp,
                    ],
                    crate::CommandEffectPoint::Immediate,
                    false,
                ),
            })
        .with_context(|| {
            format!(
                "Thread {thread_id} core Mode commit {} has been applied; product completion failed without replaying core",
                committed.commit_sequence
            )
        });
        if let Err(error) = &result {
            tracing::error!(thread_id, core_commit = committed.commit_sequence, error = %format!("{error:#}"), "Mode post-commit completion failed");
        }
        result
    }
}

struct PreparedModeApplication {
    candidate: ThreadSnapshot,
    application: RuntimeApplication,
}

struct PreparedModeInstallation {
    application: PreparedModeApplication,
    settings_revision: u64,
}

fn prepare_mode_application(
    thread_id: &str,
    state: &ThreadSnapshot,
    mode: &RegisteredThreadMode,
    config: &crate::StudioConfig,
    model: crate::config::ModelRouteConfig,
    now: i64,
) -> Result<PreparedModeApplication> {
    let mode_id = &mode.descriptor().id;
    let saved_route = crate::studio::model_route::saved(state)?;
    let service_tier = saved_route
        .as_ref()
        .filter(|saved| {
            saved.route.model.account_id == model.account_id
                && saved.route.model.model_id == model.model_id
        })
        .and_then(|saved| saved.route.service_tier.clone());
    let route_selector = crate::studio::model_route::ThreadModelSelection {
        model,
        service_tier,
    };
    let route = route_selector.resolve(config)?;
    let instruction_model = model_binding::validate_context(state, &route)?;
    let previous = state
        .extensions
        .get(INSTRUCTIONS_EXTENSION)
        .context("Thread has no saved instruction sources")?;
    // 模式切换只更新 Mode 自己拥有的来源；Agent 定义身份与角色正文保持不变。
    let mut instructions = crate::instruction::decode_snapshot(&previous.payload)?;
    let mode_changed =
        instructions.set_mode_instruction(&mode.descriptor().display_name, mode.prompt())?;
    let base_changed =
        instructions.rebind_model_base(&route.model.base.model_messages.instructions_template);
    let prompt_changed = mode_changed | base_changed;
    let complete = instructions.trusted_text();
    let hash = instructions.trusted_content_hash();
    let same_route = saved_route.is_some_and(|saved| saved.route == route_selector);
    let binding = crate::context_preparation::instruction_binding(&route, &instruction_model);
    let binding_record = state.extensions.get("studio.instructions.binding");
    let saved_binding = binding_record
        .map(crate::context_preparation::decode_instruction_binding)
        .transpose()?;
    let binding_matches = saved_binding.as_ref() == Some(&binding);
    let binding_missing = saved_binding.is_none();
    let current = crate::instruction::current_instruction_context(&state.context.records);
    let has_latest_snapshot = current.latest_snapshot().is_some();
    let latest_hash = state
        .context
        .records
        .iter()
        .rev()
        .find_map(|record| match &record.source {
            pl_core::context::ContextSource::InstructionSnapshot { content_hash, .. } => {
                Some(content_hash.clone())
            }
            _ => None,
        });
    // Canonical initial Instruction records are already current even before the first
    // InstructionSnapshot exists. Body, record shape and the frozen route capability binding
    // share one comparison with compaction recovery; workflow/Mode transaction effects remain
    // independent of this prompt no-op. A missing binding is tolerated only for this initial
    // no-snapshot state; once history has a snapshot, unknown capabilities require replacement.
    let instruction_unchanged = !prompt_changed
        && same_route
        && current.is_canonical_for(&complete)
        && (binding_matches || (binding_missing && !has_latest_snapshot));
    let (instruction_replace, instruction_binding) = if instruction_unchanged {
        (None, None)
    } else {
        let snapshot = pl_core::context::ContextRecord {
            id: format!("instruction:{thread_id}:{}", uuid::Uuid::new_v4()),
            turn_id: None,
            source: pl_core::context::ContextSource::InstructionSnapshot {
                revision: previous.revision,
                content_hash: hash.clone(),
                replaces: latest_hash,
            },
            content: vec![pl_core::context::ContextContent::Text {
                text: complete.clone().into(),
            }],
            tool_calls: Vec::new(),
        };
        let version_binding = pl_core::thread::extensions::InstructionRevisionBinding {
            record_id: snapshot.id.clone(),
            extension_id: INSTRUCTIONS_EXTENSION.into(),
        };
        let append = same_route && binding_matches && binding.append_snapshots;
        let mut records = if append {
            state.context.records.to_vec()
        } else {
            state
                .context
                .records
                .iter()
                .filter(|record| {
                    !matches!(
                        record.source,
                        pl_core::context::ContextSource::Instruction
                            | pl_core::context::ContextSource::InstructionSnapshot { .. }
                    )
                })
                .cloned()
                .collect::<Vec<_>>()
        };
        if append {
            records.push(snapshot);
        } else {
            records.insert(0, snapshot);
        }
        (
            Some(ReplaceContext {
                expected_revision: state.context.revision,
                reason: ContextReplacementReason::Rebuild,
                records,
            }),
            Some(version_binding),
        )
    };
    let workflow_record = state
        .extensions
        .get(crate::workflow_tool::WORKFLOW_EXTENSION);
    let previous_workflow = workflow_record
        .map(|record| crate::workflow_tool::decode_workflow_state(&record.payload))
        .transpose()?;
    let workflow =
        crate::workflow_tool::archive_workflow_for_mode_change(previous_workflow, mode_id, now)?;
    let mode_record = state.extensions.get(MODE_EXTENSION);
    let route_record = state
        .extensions
        .get(crate::studio::model_route::MODEL_ROUTE_EXTENSION)
        .context("Thread has no saved model route")?;
    let mode_payload =
        crate::mode::encode_mode_snapshot(&crate::mode::SavedThreadMode::capture(mode, None))?;
    let route_payload = crate::studio::model_route::encode(&route_selector)?;
    let mut mutations = vec![
        ExtensionMutation::Put {
            id: MODE_EXTENSION.into(),
            expected_revision: mode_record.map(|record| record.revision),
            payload: mode_payload.clone(),
        },
        ExtensionMutation::Put {
            id: crate::studio::model_route::MODEL_ROUTE_EXTENSION.into(),
            expected_revision: Some(route_record.revision),
            payload: route_payload.clone(),
        },
    ];
    if !instruction_unchanged {
        mutations.push(ExtensionMutation::Put {
            id: INSTRUCTIONS_EXTENSION.into(),
            expected_revision: Some(previous.revision),
            payload: crate::instruction::encode_snapshot(&instructions)?,
        });
    }
    if !binding_matches {
        mutations.push(ExtensionMutation::Put {
            id: "studio.instructions.binding".into(),
            expected_revision: binding_record.map(|record| record.revision),
            payload: pl_core::context::OpaquePayload::new(
                "pl.studio.instruction-binding",
                1,
                serde_json::to_string(&binding)?,
            )?,
        });
    }
    let mut facts = Vec::new();
    if let Some(workflow) = &workflow {
        mutations.push(ExtensionMutation::Put {
            id: crate::workflow_tool::WORKFLOW_EXTENSION.into(),
            expected_revision: workflow_record.map(|record| record.revision),
            payload: crate::workflow_tool::encode_workflow_state(workflow)?,
        });
        if let Some(section) =
            crate::workflow_tool::workflow_model_context_section(workflow, mode.workflow_binding())?
        {
            facts.push(RuntimeFact {
                source_id: "studio.workflow".into(),
                content: vec![pl_core::context::ContextContent::Text {
                    text: section.content.into(),
                }],
            });
        }
    }
    let old_workflow = state
        .runtime_facts
        .iter()
        .find(|fact| fact.source_id == "studio.workflow");
    if facts.is_empty() && old_workflow.is_some_and(|fact| !fact.content.is_empty()) {
        facts.push(RuntimeFact {
            source_id: "studio.workflow".into(),
            content: Vec::new(),
        });
    }
    let facts_changed = facts.first().is_some_and(|fact| Some(fact) != old_workflow);
    // The history writer needs an explicit context effect for changed runtime facts, even
    // when the instruction authority itself is already canonical and unchanged.
    let context_update = match instruction_replace {
        Some(replacement) => Some(replacement),
        None if facts_changed => Some(ReplaceContext {
            expected_revision: state.context.revision,
            reason: ContextReplacementReason::Rebuild,
            records: state.context.records.to_vec(),
        }),
        None => None,
    };
    let mut candidate = state.clone();
    candidate.extensions.insert(
        MODE_EXTENSION.into(),
        pl_core::thread::extensions::ExtensionRecord {
            revision: mode_record.map_or(1, |record| record.revision),
            payload: mode_payload,
        },
    );
    candidate.extensions.insert(
        crate::studio::model_route::MODEL_ROUTE_EXTENSION.into(),
        pl_core::thread::extensions::ExtensionRecord {
            revision: route_record.revision,
            payload: route_payload,
        },
    );
    Ok(PreparedModeApplication {
        candidate,
        application: RuntimeApplication {
            instruction_binding,
            update: ApplicationUpdate { mutations, facts },
            context: context_update,
        },
    })
}

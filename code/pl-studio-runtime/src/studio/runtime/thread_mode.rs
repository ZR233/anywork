//! Product Mode changes are a single idle core transaction followed by directory projection.
use super::StudioRuntime;
use crate::mode::ThreadModeId;
use crate::studio::model_binding::{self, NativeBundleOwner, NativeModelConfiguration};
use anyhow::{Context, Result};
use pl_core::thread::{
    ContextReplacementReason, ReplaceContext, RuntimeApplication, RuntimeFact,
    extensions::{ApplicationUpdate, ExtensionMutation},
};

struct ModeCompletion {
    operation_id: String,
    directory: crate::Thread,
    _lifecycle: tokio::sync::OwnedMutexGuard<()>,
    _installation: tokio::sync::OwnedMutexGuard<()>,
}

impl StudioRuntime {
    /// Explicit user reduction, serialized with prompt admission and normal context preparation.
    pub async fn compact_thread(&self, thread_id: &str) -> Result<()> {
        let lifecycle = self.lifecycle_lock.lock().await;
        self.read_owned_thread(thread_id).await?;
        anyhow::ensure!(!self.thread_is_busy(thread_id).await?, "Thread is busy");
        let thread = self.ensure_thread_owner(thread_id).await?;
        let (gate, cancellation) = self.thread_factory.tool_operation(thread_id)?;
        let _installation = tokio::select! {
            biased;
            () = cancellation.cancelled() => return Err(pl_core::thread::ThreadError::Closed.into()),
            guard = gate.lock_owned() => guard,
        };
        // The per-Thread gate now owns admission; shutdown must be able to cancel this model call.
        drop(lifecycle);
        thread
            .compact_context(thread.snapshot().context.revision, cancellation)
            .await?;
        thread.flush().await?;
        Ok(())
    }

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
        let config = self.config_runtime.read()?.config;
        let route_selector = config.mode_model_route(&mode_id)?.clone();
        let route = config
            .models
            .resolve_route(crate::config::root_agent_route_id(), &route_selector)?;

        let thread = self.ensure_thread_owner(thread_id).await?;
        let (gate, cancellation) = self.thread_factory.tool_operation(thread_id)?;
        let _installation = tokio::select! {
            biased;
            () = cancellation.cancelled() => return Err(pl_core::thread::ThreadError::Closed.into()),
            guard = gate.lock_owned() => guard,
        };
        let state = thread.snapshot();
        let instruction_model = model_binding::validate_context(&state, &route)?;
        let previous = state
            .extensions
            .get("studio.instructions")
            .context("Thread has no saved instruction sources")?;
        // 模式切换只更新 Mode 自己拥有的来源；Agent 定义身份与角色正文保持不变。
        let mut instructions = crate::instruction::decode_snapshot(&previous.payload)?;
        let mode_changed =
            instructions.set_mode_instruction(&mode.descriptor().display_name, mode.prompt())?;
        let base_changed = instructions.rebind_model_base(&route.model.base_instructions);
        let prompt_changed = mode_changed | base_changed;
        let complete = instructions.trusted_text();
        let hash = instructions.trusted_content_hash();
        let same_route = crate::studio::model_route::saved(&state)?
            .is_some_and(|saved| saved.route == route_selector);
        let binding = crate::compaction::instruction_binding(&route, &instruction_model);
        let binding_record = state.extensions.get("studio.instructions.binding");
        let saved_binding = binding_record
            .map(crate::compaction::decode_instruction_binding)
            .transpose()?;
        let binding_matches = saved_binding.as_ref() == Some(&binding);
        let binding_missing = saved_binding.is_none();
        let current = crate::instruction::current_instruction_context(&state.context.records);
        let has_latest_snapshot = current.latest_snapshot().is_some();
        let latest_hash =
            state
                .context
                .records
                .iter()
                .rev()
                .find_map(|record| match &record.source {
                    pl_core::context::ContextSource::InstructionSnapshot {
                        content_hash, ..
                    } => Some(content_hash.clone()),
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
        let instruction_replace = if instruction_unchanged {
            None
        } else {
            // The instruction Put is third in this atomic extension batch.
            let instruction_revision = state
                .extension_sequence
                .checked_add(3)
                .context("instruction revision exhausted")?;
            let snapshot = pl_core::context::ContextRecord {
                id: format!("instruction:{thread_id}:revision:{instruction_revision}"),
                turn_id: None,
                source: pl_core::context::ContextSource::InstructionSnapshot {
                    revision: instruction_revision,
                    content_hash: hash.clone(),
                    replaces: latest_hash,
                },
                content: vec![pl_core::context::ContextContent::Text {
                    text: complete.clone().into(),
                }],
                tool_calls: Vec::new(),
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
            Some(ReplaceContext {
                expected_revision: state.context.revision,
                reason: ContextReplacementReason::Rebuild,
                records,
            })
        };
        let workflow_record = state
            .extensions
            .get(crate::workflow_tool::WORKFLOW_EXTENSION);
        let previous_workflow = workflow_record
            .map(|record| crate::workflow_tool::decode_workflow_state(&record.payload))
            .transpose()?;
        let now = crate::studio::unix_seconds();
        let workflow =
            crate::mode::state::archive_workflow_for_mode_change(previous_workflow, &mode_id, now)?;
        let mode_record = state.extensions.get("studio.mode");
        let route_record = state
            .extensions
            .get(crate::studio::model_route::MODEL_ROUTE_EXTENSION)
            .context("Thread has no saved model route")?;
        let mode_payload =
            crate::mode::encode_mode_snapshot(&crate::mode::SavedThreadMode::capture(&mode, None))?;
        let route_payload = crate::studio::model_route::encode(&route_selector)?;
        let mut mutations = vec![
            ExtensionMutation::Put {
                id: "studio.mode".into(),
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
                id: "studio.instructions".into(),
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
        let mut facts = state
            .runtime_facts
            .iter()
            .filter(|fact| fact.source_id != "studio.workflow")
            .cloned()
            .collect::<Vec<_>>();
        if let Some(workflow) = &workflow {
            mutations.push(ExtensionMutation::Put {
                id: crate::workflow_tool::WORKFLOW_EXTENSION.into(),
                expected_revision: workflow_record.map(|record| record.revision),
                payload: crate::workflow_tool::encode_workflow_state(workflow)?,
            });
            if let Some(section) = crate::mode::workflow_model_context_section(workflow, &mode) {
                facts.push(RuntimeFact {
                    source_id: "studio.workflow".into(),
                    content: vec![pl_core::context::ContextContent::Text {
                        text: section.content.into(),
                    }],
                });
            }
        }
        let facts_changed = facts.len() != state.runtime_facts.len()
            || facts.iter().any(|fact| {
                !state
                    .runtime_facts
                    .iter()
                    .any(|current| current.source_id == fact.source_id && current == fact)
            });
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
            "studio.mode".into(),
            pl_core::thread::extensions::ExtensionRecord {
                revision: state.extension_sequence.saturating_add(1),
                payload: mode_payload,
            },
        );
        candidate.extensions.insert(
            crate::studio::model_route::MODEL_ROUTE_EXTENSION.into(),
            pl_core::thread::extensions::ExtensionRecord {
                revision: state.extension_sequence.saturating_add(2),
                payload: route_payload,
            },
        );
        let configuration = NativeModelConfiguration::resolve(&self.config_runtime, &candidate)?;
        let desired = format!("mode:{mode_id}:{}", configuration.desired()).into();
        let session = self.require_session(thread_id)?;
        let mut update = configuration
            .prepare_bundle(
                NativeBundleOwner {
                    id: thread_id,
                    session: &session,
                    factory: &self.thread_factory,
                    config: &self.config_runtime,
                    thread: &thread,
                    snapshot: &candidate,
                },
                cancellation,
                desired,
                || true,
            )
            .await?;
        update.application = Some(RuntimeApplication {
            expected_sequence: state.commit_sequence,
            update: ApplicationUpdate { mutations, facts },
            context: context_update,
        });
        let operation = format!("reconfigure Mode {mode_id} for Thread {thread_id}");
        let mut directory = crate::Thread::from(record);
        directory.mode = Some(mode_id);
        directory.updated_at = now;
        let completion = ModeCompletion {
            operation_id,
            directory,
            _lifecycle: lifecycle,
            _installation,
        };
        let runtime = self.clone();
        let result = self
            .rejected_tools
            .reconfigure(
                thread.clone(),
                update,
                operation,
                move |committed| async move {
                    runtime.complete_thread_mode(committed, completion).await
                },
            )
            .await;
        if result.is_err() {
            self.tool_catalog_updates.notify_one();
        }
        result
    }

    async fn complete_thread_mode(
        &self,
        committed: std::sync::Arc<pl_core::thread::ThreadSnapshot>,
        completion: ModeCompletion,
    ) -> Result<crate::ThreadModeCommandReply> {
        let ModeCompletion {
            operation_id,
            directory,
            _lifecycle,
            _installation,
        } = completion;
        let thread_id = directory.id.clone();
        self.thread_factory.notify_lsp_binding_changed();
        // The projection owner records this committed Mode before awaiting persistence.
        let directory_commit = self
            .agent_facility
            .product_events
            .commit_observed_thread_mode(
                &thread_id,
                directory.mode.context("Native root has no Mode")?,
                directory.updated_at,
            )
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

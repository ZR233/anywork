//! Product Mode changes are a single idle core transaction followed by directory projection.
use super::StudioRuntime;
use anyhow::{Context, Result};
use pl_core::thread::{
    ContextReplacementReason, IdleReconfiguration, ReplaceContext, RuntimeFact,
    extensions::{ApplicationUpdate, ExtensionMutation},
};
use pl_protocol::ThreadModeId;

#[derive(Debug, thiserror::Error)]
#[error(
    "Mode tool catalog preparation failed ({operation:#}); candidate cleanup failed ({cleanup:#})"
)]
struct ModeCandidateCleanupFailure {
    #[source]
    operation: anyhow::Error,
    cleanup: anyhow::Error,
}

struct ModeCompletion {
    operation_id: String,
    directory: pl_protocol::Thread,
    binding: crate::studio::thread_factory::RefreshedToolBinding,
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
    ) -> Result<pl_protocol::studio::ThreadModeCommandReply> {
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
            .resolve_route(crate::config::StudioRole::Planner.id(), &route_selector)?;

        let thread = self.ensure_thread_owner(thread_id).await?;
        let (gate, cancellation) = self.thread_factory.tool_operation(thread_id)?;
        let _installation = tokio::select! {
            biased;
            () = cancellation.cancelled() => return Err(pl_core::thread::ThreadError::Closed.into()),
            guard = gate.lock_owned() => guard,
        };
        let state = thread.snapshot();
        Self::validate_model_media(&state, &route.model, &[])?;
        pl_model::runtime::ThreadModel::new(
            pl_model::runtime::ModelRuntime::from_route(&route)?,
            route.reasoning_config(),
        )
        .validate_context_origin(&state.context)?;
        let previous = state
            .extensions
            .get("studio.instructions")
            .context("Thread has no saved instruction sources")?;
        // 模式切换只更新 Mode 自己拥有的来源；Agent 定义身份与角色正文保持不变。
        let mut instructions = crate::instruction::decode_snapshot(&previous.payload)?;
        instructions.set_mode_instruction(&mode.descriptor().display_name, mode.prompt())?;
        let projected = instructions.context_records(thread_id);
        let complete = projected
            .iter()
            .filter(|record| record.source == pl_core::context::ContextSource::Instruction)
            .flat_map(|record| &record.content)
            .filter_map(|content| match content {
                pl_core::context::ContextContent::Text { text } => Some(text.as_ref()),
                _ => None,
            })
            .collect::<Vec<_>>()
            .join("\n");
        let hash = pl_core::context::content_hash(complete.as_bytes());
        let replaces = state
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
                content_hash: hash,
                replaces,
            },
            content: vec![pl_core::context::ContextContent::Text {
                text: complete.into(),
            }],
            tool_calls: Vec::new(),
        };
        let same_route = crate::studio::model_route::saved(&state)?
            .is_some_and(|saved| saved.route == route_selector);
        let append = same_route
            && route.endpoint.instruction_update_strategy(&route.model)
                == pl_model::protocol::InstructionUpdateStrategy::AppendFullSnapshot;
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
            ExtensionMutation::Put {
                id: "studio.instructions".into(),
                expected_revision: Some(previous.revision),
                payload: crate::instruction::encode_snapshot(&instructions)?,
            },
        ];
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
        if let Some(fact) = self.thread_factory.session_files_fact(thread_id, &state) {
            facts.retain(|current| current.source_id != "studio.session-files");
            facts.push(fact);
        }
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
        // Every fallible side-effect-free input is prepared before physical tool candidates.
        let model_update = self.deferred_model_update(&route, &config)?;
        let (tools, exposure, binding) = self
            .thread_factory
            .refresh_thread_tools(thread_id, &candidate, cancellation.clone())
            .await?;
        let mut registrations = tools.into_registrations();
        let controls = (|| -> Result<()> {
            if exposure == crate::thread_assembler::AgentControlExposure::Enabled {
                let profiles = self.config_runtime.agent_profiles_snapshot()?;
                registrations.extend(self.threads.agent_control_tools(&profiles)?);
                if self.config_runtime.agent_profiles_snapshot()?.revision != profiles.revision {
                    return Err(pl_core::thread::ThreadError::Cancelled.into());
                }
            }
            if cancellation.is_cancelled() {
                return Err(pl_core::thread::ThreadError::Cancelled.into());
            }
            Ok(())
        })();
        if let Err(error) = controls {
            return match self
                .rejected_tools
                .retire(thread.clone(), registrations, format!("{error:#}"))
                .await
            {
                Ok(()) => Err(error),
                Err(cleanup) => {
                    self.tool_catalog_updates.notify_one();
                    Err(ModeCandidateCleanupFailure {
                        operation: error,
                        cleanup,
                    }
                    .into())
                }
            };
        }
        let operation = format!("reconfigure Mode {mode_id} for Thread {thread_id}");
        let mut directory = pl_protocol::Thread::from(record);
        directory.mode = mode_id;
        directory.updated_at = now;
        let completion = ModeCompletion {
            operation_id,
            directory,
            binding,
            _lifecycle: lifecycle,
            _installation,
        };
        let runtime = self.clone();
        let completion_thread = thread.clone();
        let result = self
            .rejected_tools
            .reconfigure(
                thread.clone(),
                IdleReconfiguration {
                    expected_sequence: state.commit_sequence,
                    application: ApplicationUpdate { mutations, facts },
                    context: Some(ReplaceContext {
                        expected_revision: state.context.revision,
                        reason: ContextReplacementReason::Rebuild,
                        records,
                    }),
                    model_update: Some(model_update),
                    replace_tools: true,
                    remove_tools: Vec::new(),
                    tools: registrations,
                },
                operation,
                move |committed| async move {
                    runtime
                        .complete_thread_mode(completion_thread, committed, completion)
                        .await
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
        thread: pl_core::thread::ThreadHandle,
        committed: pl_core::thread::ThreadSnapshot,
        completion: ModeCompletion,
    ) -> Result<pl_protocol::studio::ThreadModeCommandReply> {
        let ModeCompletion {
            operation_id,
            directory,
            binding,
            _lifecycle,
            _installation,
        } = completion;
        let thread_id = directory.id.clone();
        let binding_error = self
            .thread_factory
            .commit_refreshed_binding(&thread_id, binding)
            .err()
            .map(anyhow::Error::from);
        if let Some(error) = &binding_error {
            // Core has committed the new Mode. Repair only its tool binding using the existing
            // catalog refresh owner, never by replaying this Mode transaction.
            self.publish_tool_refresh_result(&thread_id, &thread, Some(error));
            self.tool_catalog_updates.notify_one();
        }
        // Even a binding failure cannot discard the already committed directory Mode fact.
        // The projection owner records it before awaiting IO and owns failed persistence retries.
        let directory_commit = self
            .agent_facility
            .product_events
            .commit_observed_thread(directory)
            .await;
        let result = match (binding_error, directory_commit) {
            (None, Ok(directory_commit)) => self
                .thread_directory_stamp(&directory_commit)
                .map(|directory_stamp| pl_protocol::studio::ThreadModeCommandReply {
                    receipt: self.command_receipt(
                        operation_id,
                        true,
                        vec![
                            self.resource_stamp(
                                format!("thread-state:{thread_id}"),
                                committed.commit_sequence,
                            ),
                            directory_stamp,
                        ],
                        pl_protocol::studio::CommandEffectPoint::Immediate,
                        false,
                    ),
                }),
            (Some(binding), Ok(_)) => Err(binding.context("Mode binding repair was requested")),
            (None, Err(storage)) => Err(storage.context(
                "directory Mode fact is retained by write-behind for persistence retry",
            )),
            (Some(binding), Err(storage)) => Err(storage.context(format!(
                "directory Mode fact is retained by write-behind; binding repair requested: {binding:#}"
            ))),
        }
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

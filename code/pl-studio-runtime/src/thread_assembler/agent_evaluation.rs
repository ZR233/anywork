//! Final evaluations are owned operations, not cancellable tool-side SQL futures.
use super::{StudioThreadAssembler, agent_services::AgentServices};
use anyhow::{Context, Result, ensure};
use pl_core::thread::{
    ThreadLifecycle, ThreadSnapshot, TurnState,
    input::{InputExecution, InputState},
    interactions::InteractionState,
    permissions::PermissionState,
    task::TaskStatus,
};
use pl_protocol::{
    AgentEvaluation, AgentEvaluationWrite, EvaluateAgentReceipt, EvaluateAgentRequest,
};

impl AgentServices {
    async fn evaluate_final(
        &self,
        owner: &StudioThreadAssembler,
        caller: &str,
        request: EvaluateAgentRequest,
    ) -> Result<EvaluateAgentReceipt> {
        let _operation = owner.agent_operation(&request.target).await;
        // The same gate is held through flush, terminal validation and the full SQL transaction.
        let (resident, sealed) = {
            let state = owner.0.state();
            ensure!(!state.closing, "agent coordinator is closing");
            let parent = state
                .entries
                .get(caller)
                .context("evaluation caller is not active")?;
            ensure!(
                parent.ready
                    && !state.sealed_agents.contains_key(caller)
                    && parent.parent_id.is_none()
                    && parent.thread.snapshot().lifecycle == ThreadLifecycle::Open,
                "only an active parent root may evaluate its direct child"
            );
            let sealed = state.sealed_agents.contains_key(&request.target)
                || state
                    .entries
                    .get(&request.target)
                    .is_some_and(|entry| !entry.ready);
            (
                state
                    .entries
                    .get(&request.target)
                    .map(|entry| (entry.thread.clone(), entry.incarnation.clone())),
                sealed,
            )
        };
        let record = self.record(&request.target).await?;
        ensure!(
            record.parent_thread_id.as_deref() == Some(caller) && record.root_thread_id == caller,
            "evaluate_agent target must be the caller's direct child"
        );
        // A close seal denies writes, not the receipt of an already committed identical write.
        // Read this canonical fact under the same target permit, including the interval before
        // its older checkpoint extension has been committed.
        let close = self.store.agent_close(&request.target).await?;
        if let Some(close) = &close {
            ensure!(
                close.parent_id == caller
                    && close.root_id == record.root_thread_id
                    && close.project_id == record.project_id,
                "closed evaluation target identity conflicts with its directory"
            );
        }
        ensure!(
            !self.store.has_legacy_retirement(&request.target).await?,
            "unreconciled legacy close facts cannot authorize an evaluation"
        );
        self.recovery.ensure_thread_read_access(&record)?;
        let history = self.store.history(&request.target).await?;
        let (snapshot, turn) = if let Some((thread, _)) = &resident {
            let before = thread.snapshot();
            validate_idle(&before)?;
            thread.flush().await?;
            let after = thread.snapshot();
            ensure!(
                after.commit_sequence == before.commit_sequence,
                "child changed during final evaluation validation; retry with latest state"
            );
            let turn = history.latest_turn_at(after.commit_sequence).await?;
            (after, turn)
        } else {
            // Evaluation is a strict canonical read, not a recovery entry: StateStore::load may
            // import legacy TOML or finish its cleanup even when SQLite already has a checkpoint.
            let (checkpoint, turn) = history
                .read_only_checkpoint_with_latest_turn()
                .await
                .context("cold evaluation cannot read the canonical checkpoint; use the existing open or explicit continuation/recovery entry if migration is required")?
                .context("cold child has no canonical checkpoint; migrate legacy history through the existing open or explicit continuation/recovery entry before evaluation")?;
            ensure!(
                checkpoint.history_fence == checkpoint.state.commit_sequence,
                "cold child checkpoint is not covered by its durable history"
            );
            (checkpoint.state, turn)
        };
        validate_idle(&snapshot)?;
        // Finished Turns are intentionally absent from Core's resident/checkpoint set. Resolve
        // the latest admission, including non-terminal states, from the existing history owner.
        let turn = turn.context("child has no committed Turn")?;
        ensure!(
            turn.id == request.expected_turn_id && turn.state.is_terminal(),
            "expectedTurnId is not the latest committed terminal Turn"
        );
        if let Some((thread, incarnation)) = &resident {
            let current = thread.snapshot();
            ensure!(
                current.commit_sequence == snapshot.commit_sequence
                    && owner
                        .0
                        .state()
                        .entries
                        .get(&request.target)
                        .is_some_and(|entry| std::sync::Arc::ptr_eq(
                            &entry.incarnation,
                            incarnation
                        )),
                "child changed during final evaluation history read; retry with latest state"
            );
            validate_idle(&current)?;
        }
        let (profile, _) = crate::studio::model_route::saved_profile(&snapshot)?
            .context("child has no provable frozen Profile model")?;
        ensure!(
            profile.profile_id == record.role,
            "saved child Profile identity conflicts with directory"
        );
        // Missing old provenance has the explicit legacy semantics, never today's global default.
        let delegation = match crate::studio::delegation::saved(&snapshot)? {
            Some(selection) => selection,
            None => {
                ensure!(
                    record.delegation_mode == pl_protocol::DelegationMode::Profile
                        && record.delegation_preference
                            == pl_protocol::DelegationPreference::Balanced,
                    "child has no canonical delegation provenance"
                );
                pl_protocol::DelegationSettings::default()
            }
        };
        let model = crate::studio::delegation::profile_model(&profile);
        if close.is_some()
            || sealed
            || record.archived
            || crate::studio::agent_close::is_explicitly_closed(&snapshot)?
        {
            let previous = self
                .store
                .read_agent_evaluation(&request.target)
                .await?
                .context("closed child cannot receive a new evaluation")?;
            ensure!(
                previous.agent_id == request.target
                    && previous.parent_agent_id == caller
                    && previous.model == model
                    && previous.profile_id == profile.profile_id
                    && previous.mode == delegation.mode
                    && previous.preference == delegation.preference
                    && crate::studio::store::agent_evaluations::same_content(&previous, &request),
                "closed child accepts only an already committed identical evaluation"
            );
            ensure!(
                request.expected_revision == previous.revision
                    || request.expected_revision.checked_add(1) == Some(previous.revision),
                "evaluation revision conflict"
            );
            return Ok(EvaluateAgentReceipt {
                target: request.target,
                write: AgentEvaluationWrite::Unchanged,
                evaluation: previous,
            });
        }
        self.store
            .ensure_agent_execution_allowed(&request.target)
            .await?;
        let now = crate::studio::unix_seconds();
        let candidate = AgentEvaluation {
            agent_id: request.target.clone(),
            parent_agent_id: caller.into(),
            model,
            profile_id: profile.profile_id,
            mode: delegation.mode,
            preference: delegation.preference,
            turn_id: request.expected_turn_id.clone(),
            revision: 0,
            task_category: request.task_category,
            outcome: request.outcome,
            quality: request.quality,
            instruction_following: request.instruction_following,
            comment: request.comment.clone(),
            created_at: now,
            updated_at: now,
        };
        self.store.write_agent_evaluation(&request, candidate).await
    }
}

fn validate_idle(snapshot: &ThreadSnapshot) -> Result<()> {
    ensure!(
        !matches!(
            snapshot.input_execution,
            InputExecution::Interrupting { .. }
        ) && !snapshot
            .turns
            .iter()
            .any(|turn| turn.state == TurnState::Running)
            && !snapshot
                .tasks
                .values()
                .any(|task| task.status == TaskStatus::Running)
            && !snapshot
                .inputs
                .iter()
                .any(|input| input.state == InputState::Pending)
            && !snapshot
                .inbox
                .iter()
                .any(|message| message.sequence > snapshot.consumed_messages)
            && !snapshot
                .interactions
                .values()
                .any(|interaction| interaction.state == InteractionState::Pending)
            && !snapshot
                .permissions
                .values()
                .any(|permission| permission.state == PermissionState::Pending),
        "child still has running work, pending input, interaction or permission"
    );
    Ok(())
}

impl StudioThreadAssembler {
    pub(super) async fn evaluate_agent(
        &self,
        caller: String,
        request: EvaluateAgentRequest,
    ) -> Result<EvaluateAgentReceipt> {
        request.validate()?;
        let services = self
            .0
            .state()
            .agent_services
            .clone()
            .context("evaluation services are unavailable")?;
        let owner = self.clone();
        let operation_owner = owner.clone();
        let root = caller.clone();
        services
            .operations
            .clone()
            .run(
                caller.clone(),
                move || {
                    owner.ensure_agent_admission_open(&root)?;
                    ensure!(
                        owner
                            .0
                            .state()
                            .entries
                            .get(&root)
                            .is_some_and(|entry| entry.parent_id.is_none()),
                        "evaluation caller is not an active root"
                    );
                    Ok(())
                },
                async move {
                    services
                        .evaluate_final(&operation_owner, &caller, request)
                        .await
                },
            )
            .await
    }
}

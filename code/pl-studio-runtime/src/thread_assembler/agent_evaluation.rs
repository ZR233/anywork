//! Final evaluations are owned operations, not cancellable tool-side SQL futures.
use super::{SessionRuntime, agent_services::AgentServices};
use crate::{AgentEvaluation, EvaluateAgentReceipt, EvaluateAgentRequest};
use anyhow::{Context, Result, ensure};
use pl_core::thread::{
    ThreadLifecycle, ThreadSnapshot, TurnState,
    input::{InputExecution, InputState},
    interactions::InteractionState,
    permissions::PermissionState,
    task::TaskStatus,
};

impl AgentServices {
    async fn evaluate_final(
        &self,
        owner: &SessionRuntime,
        caller: &str,
        request: EvaluateAgentRequest,
    ) -> Result<EvaluateAgentReceipt> {
        let _operation = owner.agent_operation(&request.target).await;
        let record = self.record(&request.target).await?;
        ensure!(
            self.direct_child(caller, &request.target)?,
            "evaluate_agent target must be the caller's direct child"
        );
        let thread = {
            let state = owner.0.state();
            ensure!(!state.closing, "agent coordinator is closing");
            let parent = state
                .entries
                .get(caller)
                .context("evaluation caller is not active")?;
            ensure!(
                parent.native()?.ready
                    && !state.sealed_agents.contains_key(caller)
                    && parent.identity.parent_agent_id.is_none()
                    && parent.native()?.thread.snapshot().lifecycle == ThreadLifecycle::Open,
                "only an active parent root may evaluate its direct child"
            );
            ensure!(
                !state.sealed_agents.contains_key(&request.target) && !record.archived,
                "evaluation target is closing or archived"
            );
            let target = state
                .entries
                .get(&request.target)
                .context("evaluation target has no current owner")?
                .native()?;
            ensure!(target.ready, "evaluation target is not ready");
            target.thread.clone()
        };
        let snapshot = thread.snapshot();
        validate_idle(&snapshot)?;
        ensure!(
            !crate::studio::agent_close::is_explicitly_closed(&snapshot)?,
            "closed child cannot receive a new evaluation"
        );
        let turn = owner
            .current_terminal_turn(&request.target)
            .context("child has no current terminal delivery")?;
        ensure!(
            turn.id == request.expected_turn_id && turn.state.is_terminal(),
            "expectedTurnId is not the current terminal delivery"
        );
        let (profile, _) = crate::studio::model_route::saved_profile(&snapshot)?
            .context("child has no frozen Profile model")?;
        ensure!(
            profile.profile_id == record.role,
            "child Profile identity conflicts with directory"
        );
        let delegation = crate::studio::delegation::saved(&snapshot)?
            .context("child has no delegation provenance")?;
        let now = crate::studio::unix_seconds();
        let candidate = AgentEvaluation {
            agent_id: request.target.clone(),
            parent_agent_id: caller.into(),
            model: crate::studio::delegation::profile_model(&profile),
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

pub(crate) fn validate_idle(snapshot: &ThreadSnapshot) -> Result<()> {
    ensure!(
        snapshot.execution.is_none()
            && snapshot.model_execution.is_none()
            && snapshot.pending_tool_commits.is_empty()
            && snapshot.deliveries.is_empty()
            && !matches!(
                snapshot.input_execution,
                InputExecution::Interrupting { .. }
            )
            && !snapshot
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

impl SessionRuntime {
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
                format!(
                    "evaluate:{}",
                    pl_core::context::content_hash(serde_json::to_string(&request)?.as_bytes())
                ),
                move || {
                    owner.ensure_agent_admission_open(&root)?;
                    ensure!(
                        owner
                            .0
                            .state()
                            .entries
                            .get(&root)
                            .is_some_and(|entry| entry.identity.parent_agent_id.is_none()),
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

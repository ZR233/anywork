//! Final evaluations are owned operations, not cancellable tool-side SQL futures.
use super::{SessionRuntime, agent_services::AgentServices};
use crate::{AgentEvaluation, EvaluateAgentReceipt, EvaluateAgentRequest};
use anyhow::{Context, Result, ensure};
use pl_core::{
    context::AgentMessageKind,
    thread::{
        ThreadLifecycle, ThreadSnapshot, ToolDelivery, ToolDeliveryTarget, TurnState,
        inbox::InboxRecord,
        input::{InputExecution, InputState},
        interactions::InteractionState,
        permissions::PermissionState,
        task::{TaskRecord, TaskStatus},
    },
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
            ensure!(!state.close.closing, "agent coordinator is closing");
            let parent = state
                .members
                .entries
                .get(caller)
                .context("evaluation caller is not active")?;
            ensure!(
                parent.native()?.ready
                    && !state.close.sealed_agents.contains_key(caller)
                    && parent.identity.parent_agent_id.is_none()
                    && parent.native()?.thread.snapshot().lifecycle == ThreadLifecycle::Open,
                "only an active parent root may evaluate its direct child"
            );
            ensure!(
                !state.close.sealed_agents.contains_key(&request.target) && !record.archived,
                "evaluation target is closing or archived"
            );
            let target = state
                .members
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

fn settled_background_task<'a>(
    snapshot: &'a ThreadSnapshot,
    source_id: &str,
) -> Option<&'a TaskRecord> {
    snapshot
        .tasks
        .get(source_id)
        .or_else(|| {
            snapshot
                .terminal_tasks
                .iter()
                .find(|task| task.id == source_id)
        })
        .filter(|task| task.acknowledgement.is_some() && task.status != TaskStatus::Running)
}

fn is_settled_background_inbox_record(snapshot: &ThreadSnapshot, record: &InboxRecord) -> bool {
    record.sequence > snapshot.wake_messages_through
        && record.message.kind == AgentMessageKind::Report
        && settled_background_task(snapshot, &record.message.source_id).is_some()
}

fn is_settled_background_delivery(snapshot: &ThreadSnapshot, delivery: &ToolDelivery) -> bool {
    let ToolDeliveryTarget::Inbox { message_id } = &delivery.target else {
        return false;
    };
    snapshot.inbox.iter().any(|record| {
        record.message.id == *message_id
            && record.sequence > snapshot.consumed_messages
            && is_settled_background_inbox_record(snapshot, record)
            && settled_background_task(snapshot, &record.message.source_id)
                .is_some_and(|task| task.call_id == delivery.call_id)
    })
}

pub(crate) fn validate_idle(snapshot: &ThreadSnapshot) -> Result<()> {
    ensure!(
        snapshot.execution.is_none()
            && snapshot.model_execution.is_none()
            && snapshot.wake_messages_through <= snapshot.consumed_messages
            && snapshot
                .deliveries
                .iter()
                .all(|delivery| is_settled_background_delivery(snapshot, delivery))
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
            && !snapshot.inbox.iter().any(|message| {
                message.sequence > snapshot.consumed_messages
                    && !is_settled_background_inbox_record(snapshot, message)
            })
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
                            .members
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

#[cfg(test)]
mod tests {
    use super::validate_idle;
    use anyhow::Result;
    use pl_core::{
        context::{AgentMessageKind, ContextContent, OpaquePayload},
        model::ModelToolCall,
        thread::{
            ThreadSnapshot, ToolDelivery, ToolDeliveryTarget, ToolOutcome,
            inbox::{InboxRecord, ThreadMessage},
            task::{TaskAcknowledgement, TaskRecord, TaskStatus},
        },
        tool::ToolOutput,
    };
    use std::sync::Arc;

    fn task_record(call_id: &str, status: TaskStatus, acknowledged: bool) -> TaskRecord {
        TaskRecord {
            id: format!("task:{call_id}"),
            parent_call_id: None,
            invocation: Some(ModelToolCall {
                call_id: call_id.into(),
                tool_id: "exec".into(),
                arguments: OpaquePayload::text("{}"),
                presentation_contract: None,
                rejection: None,
            }),
            call_id: call_id.into(),
            tool_id: "exec".into(),
            turn_id: "turn-1".into(),
            revision: 3,
            status,
            cancel_requested: false,
            acknowledgement: acknowledged.then(|| TaskAcknowledgement {
                record_id: "task-receipt:1".into(),
                context_revision: 12,
            }),
            started_sequence: Some(5),
        }
    }

    fn inbox_record(sequence: u64, message_id: &str, source_id: &str) -> InboxRecord {
        InboxRecord {
            sequence,
            message: ThreadMessage {
                kind: AgentMessageKind::Report,
                id: message_id.into(),
                source_id: source_id.into(),
                payload: OpaquePayload::text("done"),
                context: vec![ContextContent::Text {
                    text: Arc::from("done"),
                }],
            },
        }
    }

    fn inbox_delivery(call_id: &str, message_id: &str, outcome: ToolOutcome) -> ToolDelivery {
        ToolDelivery {
            target: ToolDeliveryTarget::Inbox {
                message_id: message_id.into(),
            },
            call_id: call_id.into(),
            tool_id: "exec".into(),
            output: ToolOutput::new(OpaquePayload::text("done"), vec![]),
            delivered_context: vec![],
            outcome,
        }
    }

    #[test]
    fn validate_idle_allows_settled_non_waking_background_results_and_rejects_live_work()
    -> Result<()> {
        for (case, snapshot, expected_ok) in [
            ("empty-idle", ThreadSnapshot::default(), true),
            (
                "hot-settled-succeeded-background-result",
                {
                    let mut s = ThreadSnapshot {
                        inbox_sequence: 3,
                        consumed_messages: 2,
                        wake_messages_through: 1,
                        inbox: Arc::from([inbox_record(3, "task-result:3", "task:call-bg")]),
                        deliveries: Arc::from([inbox_delivery(
                            "call-bg",
                            "task-result:3",
                            ToolOutcome::Succeeded,
                        )]),
                        ..Default::default()
                    };
                    s.tasks.insert(
                        "task:call-bg".into(),
                        task_record("call-bg", TaskStatus::Succeeded, true),
                    );
                    s
                },
                true,
            ),
            (
                "hot-settled-failed-and-cancelled-background-results",
                {
                    let mut s = ThreadSnapshot {
                        inbox_sequence: 4,
                        consumed_messages: 2,
                        wake_messages_through: 1,
                        inbox: Arc::from([
                            inbox_record(3, "task-result:3", "task:call-fail"),
                            inbox_record(4, "task-result:4", "task:call-cancel"),
                        ]),
                        deliveries: Arc::from([
                            inbox_delivery(
                                "call-fail",
                                "task-result:3",
                                ToolOutcome::Failed(Arc::new(
                                    pl_core::tool::opaque::ToolError::new(std::io::Error::other(
                                        "boom",
                                    )),
                                )),
                            ),
                            inbox_delivery("call-cancel", "task-result:4", ToolOutcome::Cancelled),
                        ]),
                        ..Default::default()
                    };
                    s.tasks.insert(
                        "task:call-fail".into(),
                        task_record("call-fail", TaskStatus::Failed, true),
                    );
                    s.tasks.insert(
                        "task:call-cancel".into(),
                        task_record("call-cancel", TaskStatus::Cancelled, true),
                    );
                    s
                },
                true,
            ),
            (
                "cold-reopened-settled-non-waking-background-result",
                ThreadSnapshot {
                    inbox_sequence: 3,
                    consumed_messages: 2,
                    wake_messages_through: 1,
                    inbox: Arc::from([inbox_record(3, "task-result:3", "task:call-bg")]),
                    terminal_tasks: Arc::from([task_record(
                        "call-bg",
                        TaskStatus::Succeeded,
                        true,
                    )]),
                    ..Default::default()
                },
                true,
            ),
            (
                "running-background-task",
                {
                    let mut s = ThreadSnapshot::default();
                    s.tasks.insert(
                        "task:call-run".into(),
                        task_record("call-run", TaskStatus::Running, true),
                    );
                    s
                },
                false,
            ),
            (
                "waking-background-result-must-reject",
                {
                    let mut s = ThreadSnapshot {
                        inbox_sequence: 3,
                        consumed_messages: 2,
                        wake_messages_through: 3,
                        inbox: Arc::from([inbox_record(3, "task-result:3", "task:call-bg")]),
                        deliveries: Arc::from([inbox_delivery(
                            "call-bg",
                            "task-result:3",
                            ToolOutcome::Succeeded,
                        )]),
                        ..Default::default()
                    };
                    s.tasks.insert(
                        "task:call-bg".into(),
                        task_record("call-bg", TaskStatus::Succeeded, true),
                    );
                    s
                },
                false,
            ),
            (
                "non-task-unconsumed-inbox-message-must-reject",
                ThreadSnapshot {
                    inbox_sequence: 3,
                    consumed_messages: 2,
                    wake_messages_through: 1,
                    inbox: Arc::from([inbox_record(3, "agent-msg:3", "agent:root")]),
                    ..Default::default()
                },
                false,
            ),
            (
                "non-inbox-delivery-must-reject",
                ThreadSnapshot {
                    deliveries: Arc::from([ToolDelivery {
                        target: ToolDeliveryTarget::CallResult,
                        call_id: "call-fg".into(),
                        tool_id: "exec".into(),
                        output: ToolOutput::new(OpaquePayload::text("done"), vec![]),
                        delivered_context: vec![],
                        outcome: ToolOutcome::Succeeded,
                    }]),
                    ..Default::default()
                },
                false,
            ),
            (
                "mismatched-call-id-delivery-must-reject",
                {
                    let mut s = ThreadSnapshot {
                        inbox_sequence: 3,
                        consumed_messages: 2,
                        wake_messages_through: 1,
                        inbox: Arc::from([inbox_record(3, "task-result:3", "task:call-bg")]),
                        deliveries: Arc::from([inbox_delivery(
                            "call-other",
                            "task-result:3",
                            ToolOutcome::Succeeded,
                        )]),
                        ..Default::default()
                    };
                    s.tasks.insert(
                        "task:call-bg".into(),
                        task_record("call-bg", TaskStatus::Succeeded, true),
                    );
                    s
                },
                false,
            ),
        ] {
            let actual = validate_idle(&snapshot);
            assert_eq!(
                actual.is_ok(),
                expected_ok,
                "case `{case}` returned {actual:?}"
            );
        }
        Ok(())
    }
}

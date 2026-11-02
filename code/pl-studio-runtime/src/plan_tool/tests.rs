use super::*;
use pl_core::{
    context::{ContextContent, OpaquePayload},
    model::{
        DynModelSession, ModelError, ModelRequest, ModelSession, ModelStepOutput, ModelToolCall,
        ModelTurnAction, PreparedModelCall,
    },
    thread::{
        ModelStepLimit, ThreadHandle, TurnInput, TurnOutcome, extensions::ExtensionMutation,
        interactions::InteractionState,
    },
};
use std::sync::Arc;

struct PlanningModel {
    requests: usize,
}

impl ModelSession for PlanningModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        self.requests += 1;
        let step = self.requests;
        assert!(step <= 2, "plan submission must suspend for confirmation");
        let calls = if step == 1 {
            Vec::new()
        } else {
            assert!(request.context.records.iter().any(|record| {
                record.content.contains(&ContextContent::Text {
                    text: Arc::from("调查完成，接下来提交计划。"),
                })
            }));
            vec![ModelToolCall {
                call_id: "submit-plan".into(),
                tool_id: TOOL_PLAN_SUBMIT.into(),
                arguments: OpaquePayload::new(
                    "application/json", 1,
                    serde_json::json!({"expectedRevision":0,"plan":"# 修复计划\n\n确认根因、实施修复并验证。"}).to_string(),
                ).unwrap(),
                presentation_contract: None,
                rejection: None,
            }]
        };
        Ok(PreparedModelCall::new(async move {
            Ok(ModelStepOutput {
                turn_action: ModelTurnAction::Continue,
                attempt_id: request.attempt_id,
                base_context_revision: request.context.revision,
                content: if step == 1 {
                    vec![ContextContent::Text {
                        text: Arc::from("调查完成，接下来提交计划。"),
                    }]
                } else {
                    Vec::new()
                },
                tool_calls: calls,
                private_context: None,
                usage: Default::default(),
            })
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[tokio::test]
async fn planning_progress_continues_to_real_plan_confirmation() {
    let thread = ThreadHandle::start(
        "planning-thread".into(),
        DynModelSession::new(PlanningModel { requests: 0 }),
    )
    .unwrap();
    thread
        .register_tools(plan_registrations(Default::default()).unwrap())
        .await
        .unwrap();
    thread
        .mutate_extensions(vec![ExtensionMutation::Put {
            id: PLAN_EXTENSION.into(),
            expected_revision: None,
            payload: encode_plan_state(&Default::default()).unwrap(),
        }])
        .await
        .unwrap();
    let completion = thread
        .run_turn(TurnInput {
            turn_id: "planning-turn".into(),
            attempt_prefix: "planning-attempt".into(),
            content: vec![ContextContent::Text {
                text: Arc::from("修复并提 PR"),
            }],
            max_model_steps: ModelStepLimit::Limited(3.try_into().unwrap()),
            cancellation: Default::default(),
        })
        .await
        .unwrap();
    assert_eq!(completion.model_steps, 2);
    assert_eq!(completion.outcome, TurnOutcome::WaitingInteraction);
    let snapshot = thread.snapshot();
    let plan = decode_plan_state(&snapshot.extensions[PLAN_EXTENSION].payload).unwrap();
    assert_eq!(
        plan.state,
        pl_protocol::AgentSessionPlanPhase::AwaitingConfirmation
    );
    let pending = &snapshot.interactions[plan.pending_interaction_id.as_ref().unwrap()];
    assert_eq!(pending.state, InteractionState::Pending);
    assert_eq!(pending.request.turn_id, "planning-turn");
    assert!(plan.document.unwrap().markdown.starts_with("# 修复计划"));
    thread.close().await.unwrap();
}

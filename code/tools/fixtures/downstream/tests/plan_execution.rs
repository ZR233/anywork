use pl_agent_tool::{Tool, typed::{TypedTool, prepare_json}};
use plan::{MemoryPlanHost, Plan, PlanErrorCode, PlanState, PlanTransitionArgs, PlanTransitionTool, plan_tool_family};
use std::sync::Arc;

#[tokio::test]
async fn independent_downstream_executes_plan_tool_family() {
    let host = Arc::new(MemoryPlanHost::new(Plan::new()));
    let family = plan_tool_family(Arc::clone(&host));

    let rejected = PlanTransitionTool::execute(
        &family.transition,
        PlanTransitionArgs {
            target_state: PlanState::Approved,
            content: None,
            feedback: None,
            reason: None,
            force: false,
            expected_revision: None,
            idempotency_key: None,
        },
        (),
    )
    .await
    .unwrap();
    assert!(!rejected.accepted);
    assert_eq!(rejected.error.unwrap().code, PlanErrorCode::TransitionNotAllowed);

    let prepared = prepare_json::<PlanTransitionTool<MemoryPlanHost>>()
        .unwrap()
        .attach(family.transition);
    let raw = serde_json::json!({
        "targetState": "approved",
        "content": "# Independent Plan",
        "force": true,
        "reason": "Downstream verified"
    })
    .to_string();
    let accepted = prepared.execute(raw, ()).await.unwrap();
    assert!(accepted.accepted);
    assert!(accepted.forced);
    assert_eq!(accepted.snapshot.state, PlanState::Approved);
    assert_eq!(host.snapshot().unwrap().revision, 1);
}

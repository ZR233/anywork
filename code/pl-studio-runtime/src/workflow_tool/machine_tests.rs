use super::*;
use crate::thread_mode_id::ThreadModeId;
use crate::workflow_tool::{
    WorkflowDefinition, WorkflowRunLifecycle, WorkflowSessionState, WorkflowState,
    WorkflowStateKind, WorkflowTransition, compile_workflow_definition,
};
use std::sync::Arc;

fn fixture_machine() -> WorkflowMachine {
    let graph = compile_workflow_definition(WorkflowDefinition {
        title: "Fixture".into(),
        goal: "exercise the machine without mode.auto".into(),
        initial_state_id: "intake".into(),
        states: vec![
            WorkflowState {
                id: "intake".into(),
                title: "Intake".into(),
                instructions: "start".into(),
                completion_criteria: vec!["started".into()],
                kind: WorkflowStateKind::Atomic,
            },
            WorkflowState {
                id: "review".into(),
                title: "Review".into(),
                instructions: "review".into(),
                completion_criteria: vec!["reviewed".into()],
                kind: WorkflowStateKind::Atomic,
            },
            WorkflowState {
                id: "done".into(),
                title: "Done".into(),
                instructions: String::new(),
                completion_criteria: vec![],
                kind: WorkflowStateKind::Final,
            },
        ],
        transitions: vec![
            WorkflowTransition {
                source_state_id: "intake".into(),
                target_state_id: "review".into(),
                guard: "review is ready".into(),
            },
            WorkflowTransition {
                source_state_id: "review".into(),
                target_state_id: "done".into(),
                guard: "review is complete".into(),
            },
        ],
    })
    .expect("fixture graph");
    let binding = WorkflowBinding {
        mode_id: ThreadModeId::new("mode.fixture").expect("fixture mode id"),
        graph_revision: 1,
        graph: Arc::new(graph),
    };
    let run = new_run(&binding, None, "test-seed", 100);
    let state = WorkflowSessionState {
        revision: 1,
        current_run: Some(run),
        archived_runs: Vec::new(),
        archived_run_count: 0,
        archived_run_digest: String::new(),
        operation_receipts: Vec::new(),
    };
    WorkflowMachine::new(binding, state)
}

fn completion(reason: &str) -> CompletionInput {
    CompletionInput {
        reason: reason.into(),
        summary: "stage summary".into(),
        evidence: vec!["unit test evidence".into()],
    }
}

#[test]
fn non_forced_unknown_target_and_disallowed_transition_return_rich_hints() {
    let mut machine = fixture_machine();
    let state = machine.state();
    let run_id = state.current_run.as_ref().unwrap().run_id.clone();
    let revision = state.revision;
    let err_unknown = machine
        .apply_transition(
            TransitionInput {
                expected_run_id: run_id.clone(),
                expected_revision: revision,
                expected_state_id: "intake".into(),
                target_state_id: "nonexistent".into(),
                force: false,
                completion: completion("invalid target"),
            },
            &WorkflowOperation {
                turn_id: "t1".into(),
                call_id: "c1".into(),
            },
            "h1".into(),
            101,
        )
        .unwrap();
    let WorkflowMutationResponse::Rejected { code, error, .. } = err_unknown else {
        panic!("expected a rejection for an unknown target");
    };
    assert_eq!(code, "unknownTargetState");
    assert!(error.all_states.iter().any(|s| s.id == "intake"));
    assert!(error.all_states.iter().any(|s| s.id == "review"));
    assert!(error.all_states.iter().any(|s| s.id == "done"));
    assert!(!error.allowed_transitions.is_empty());

    let err_disallowed = machine
        .apply_transition(
            TransitionInput {
                expected_run_id: run_id.clone(),
                expected_revision: revision,
                expected_state_id: "intake".into(),
                target_state_id: "done".into(),
                force: false,
                completion: completion("skip directly"),
            },
            &WorkflowOperation {
                turn_id: "t1".into(),
                call_id: "c2".into(),
            },
            "h2".into(),
            102,
        )
        .unwrap();
    let WorkflowMutationResponse::Rejected {
        code,
        recovery_action,
        error,
        ..
    } = err_disallowed
    else {
        panic!("expected a rejection for a disallowed transition");
    };
    assert_eq!(code, "transitionNotAllowed");
    assert!(recovery_action.contains("force=true"));
    assert_eq!(error.current_state_id.as_deref(), Some("intake"));
    assert_eq!(error.attempted_target_state_id.as_deref(), Some("done"));
    assert!(
        error
            .allowed_transitions
            .iter()
            .any(|edge| edge.target_state_id == "review" && !edge.guard.is_empty())
    );
}

#[test]
fn forced_transition_jumps_anywhere_including_out_of_final_state() {
    let mut machine = fixture_machine();
    let run_id = machine.state().current_run.as_ref().unwrap().run_id.clone();
    assert_eq!(run_id, "run-d63cd08d82aa4eb48e0cc64f");
    // Forced jump directly from `intake` to terminal `done`.
    let jump_final = machine
        .apply_transition(
            TransitionInput {
                expected_run_id: run_id.clone(),
                expected_revision: 1,
                expected_state_id: "intake".into(),
                target_state_id: "done".into(),
                force: true,
                completion: completion("force complete"),
            },
            &WorkflowOperation {
                turn_id: "t1".into(),
                call_id: "c1".into(),
            },
            "h1".into(),
            101,
        )
        .unwrap();
    assert!(matches!(
        jump_final,
        WorkflowMutationResponse::Accepted { forced: true, .. }
    ));
    assert_eq!(
        machine.state().current_run.as_ref().unwrap().lifecycle,
        WorkflowRunLifecycle::Terminal
    );

    // Forced jump out of terminal `done` back into `review`.
    let jump_back = machine
        .apply_transition(
            TransitionInput {
                expected_run_id: run_id,
                expected_revision: machine.state().revision,
                expected_state_id: "done".into(),
                target_state_id: "review".into(),
                force: true,
                completion: completion("reopen into planning"),
            },
            &WorkflowOperation {
                turn_id: "t2".into(),
                call_id: "c2".into(),
            },
            "h2".into(),
            102,
        )
        .unwrap();
    assert!(matches!(
        jump_back,
        WorkflowMutationResponse::Accepted { forced: true, .. }
    ));
    let run = machine.state().current_run.as_ref().unwrap();
    assert_eq!(run.current_state_id, "review");
    assert_eq!(run.lifecycle, WorkflowRunLifecycle::Active);
    assert!(run.history_tail.iter().all(|rec| rec.forced));
    assert_eq!(run.updated_at, 102);
    assert_eq!(run.history_tail[0].transitioned_at, 101);
    assert_eq!(run.history_tail[1].transitioned_at, 102);
}

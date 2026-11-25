use super::*;
use pl_core::model::{ActiveModelProgress, AggregateChannel, ObservedPartIdentity};
use pl_core::thread::{
    ActiveExecution,
    interactions::{InteractionRecord, InteractionRequest},
};
use std::sync::Arc;

fn running_state(text: &str) -> ThreadSnapshot {
    let attempt: RequestAttempt = serde_json::from_value(serde_json::json!({
        "turnId": "turn",
        "attemptId": "attempt",
        "retryOf": null,
        "inputRevision": 0,
        "status": {"kind": "running"}
    }))
    .unwrap();
    ThreadSnapshot {
        turns: Arc::from([TurnRecord {
            turn_id: "turn".into(),
            input_id: Some("input".into()),
            state: TurnState::Running,
            model_steps: 1,
            elapsed_ms: None,
        }]),
        attempts: Arc::from([attempt]),
        model_progress: Some(ActiveModelProgress {
            attempt_id: "attempt".into(),
            progress: ModelProgress::new(
                1,
                vec![
                    ObservedPart::new(ObservedPartIdentity::Aggregate {
                        channel: AggregateChannel::Text,
                    })
                    .appended(text),
                ],
            ),
        }),
        ..Default::default()
    }
}

#[test]
fn admitted_activity_excludes_completed_text_and_survives_missing_progress_window() {
    let mut state = running_state("TEXT_A");
    let generation = state
        .model_progress
        .as_ref()
        .unwrap()
        .progress
        .observation()
        .generation;
    let reasoning = ObservedPart::new(ObservedPartIdentity::Aggregate {
        channel: AggregateChannel::Reasoning,
    });
    let (id, _, shape) = super::super::observation_parts::observation_preview(
        "attempt",
        generation,
        &reasoning,
        &crate::ThreadContentLifecycle::streaming(),
    )
    .unwrap();
    let item = crate::ExecutionItem::new(
        id,
        crate::ItemStamp {
            thread_id: std::borrow::Cow::Borrowed("thread"),
            turn_id: std::borrow::Cow::Borrowed("turn"),
            ordinal: 1,
            revision: 1,
            created_at: 10,
            updated_at: 10,
        },
        shape,
    );
    let mut atom = crate::studio::runtime::chat_item::atom(&item);
    atom.attempt_id = Some("attempt".into());
    let thinking = project_activity_using(
        "thread",
        &state,
        None,
        Some(&AdmittedActivity::new(&state, &[atom], &[])),
    )
    .unwrap();
    assert_eq!(thinking.kind, ThreadActivityKind::Thinking);
    assert!(!thinking.summary.contains("TEXT_A"));
    assert_eq!(thinking.summary, "");

    let response = &state.model_progress.as_ref().unwrap().progress.parts()[0];
    let (id, _, shape) = super::super::observation_parts::observation_preview(
        "attempt",
        generation,
        response,
        &crate::ThreadContentLifecycle::streaming(),
    )
    .unwrap();
    let item = crate::ExecutionItem::new(
        id,
        crate::ItemStamp {
            thread_id: std::borrow::Cow::Borrowed("thread"),
            turn_id: std::borrow::Cow::Borrowed("turn"),
            ordinal: 2,
            revision: 1,
            created_at: 11,
            updated_at: 11,
        },
        shape,
    );
    let mut atom = crate::studio::runtime::chat_item::atom(&item);
    atom.attempt_id = Some("attempt".into());
    state.model_progress = None;
    let responding = project_activity_using(
        "thread",
        &state,
        Some(&thinking),
        Some(&AdmittedActivity::new(&state, &[atom], &[])),
    )
    .unwrap();
    assert_eq!(responding.kind, ThreadActivityKind::Responding);
    assert_eq!(responding.summary, "");
    assert_eq!(responding.thinking_summary, None);
}

#[test]
fn pre_turn_execution_uses_real_identity_in_all_five_phases() {
    let mut projection = ActivityProjection::default();
    for (phase, kind) in [
        (ExecutionPhase::Preparing, ThreadActivityKind::Preparing),
        (
            ExecutionPhase::AwaitingStorage,
            ThreadActivityKind::Preparing,
        ),
        (
            ExecutionPhase::AwaitingAdmission,
            ThreadActivityKind::Preparing,
        ),
        (ExecutionPhase::Running, ThreadActivityKind::Preparing),
        (ExecutionPhase::Stopping, ThreadActivityKind::Stopping),
    ] {
        let state = ThreadSnapshot {
            execution: Some(ActiveExecution {
                id: "opaque-execution:id".into(),
                phase,
                turn_id: None,
            }),
            // Without a Turn this unrelated model phase is not a provider call fact.
            model_execution: Some(ModelExecutionPhase::Running),
            ..Default::default()
        };
        let activity = projection.observe("thread", &state).unwrap();
        assert_eq!(activity.turn_id, None);
        assert_eq!(
            activity.execution_id.as_deref(),
            Some("opaque-execution:id")
        );
        assert_eq!(activity.kind, kind);
        assert_eq!(
            activity.identity,
            ThreadActivity::identity("opaque-execution:id", "preparing", kind)
        );
        assert!(
            projection
                .versions
                .as_ref()
                .is_none_or(|versions| versions.model.is_none())
        );
    }
    assert!(
        projection
            .observe("thread", &ThreadSnapshot::default())
            .is_none()
    );
    assert!(projection.current().is_none());
}

#[test]
fn turn_admission_preserves_the_execution_identity() {
    let mut state = ThreadSnapshot {
        execution: Some(ActiveExecution {
            id: "execution".into(),
            phase: ExecutionPhase::Preparing,
            turn_id: None,
        }),
        ..Default::default()
    };
    let mut projection = ActivityProjection::default();
    let preparing = projection.observe("thread", &state).unwrap();
    state.turns = running_state("").turns;
    state.execution.as_mut().unwrap().phase = ExecutionPhase::Running;
    state.execution.as_mut().unwrap().turn_id = Some("turn".into());
    let admitted = projection.observe("thread", &state).unwrap();
    assert_eq!(admitted.turn_id.as_deref(), Some("turn"));
    assert_eq!(admitted.execution_id.as_deref(), Some("execution"));
    assert_eq!(preparing.identity, admitted.identity);
}

fn conflicting_sources() -> ThreadSnapshot {
    let mut state = running_state("foreground response");
    state.execution = Some(ActiveExecution {
        id: "execution".into(),
        phase: ExecutionPhase::Running,
        turn_id: Some("turn".into()),
    });
    state.tasks.insert(
        "background".into(),
        TaskRecord {
            parent_call_id: None,
            invocation: None,
            id: "background".into(),
            call_id: "background-call".into(),
            tool_id: "exec".into(),
            turn_id: "background-turn".into(),
            revision: 1,
            status: TaskStatus::Running,
            cancel_requested: true,
            acknowledgement: None,
            started_sequence: Some(5),
        },
    );
    state.interactions.insert(
        "question".into(),
        InteractionRecord {
            created_at: 1,
            updated_at: 1,
            continuation_id: None,
            request: InteractionRequest {
                id: "question".into(),
                turn_id: "question-turn".into(),
                payload: pl_core::context::OpaquePayload::new("test.question", 1, "{}").unwrap(),
            },
            revision: 1,
            state: InteractionState::Pending,
            extension_mutations: vec![],
        },
    );
    state
}

#[test]
fn running_turn_keeps_ownership_with_unrelated_tool_and_question() {
    let state = conflicting_sources();
    for (has_attempt, execution_turn, kind, execution_id) in [
        (
            true,
            "turn",
            ThreadActivityKind::Responding,
            Some("execution"),
        ),
        (
            false,
            "turn",
            ThreadActivityKind::Preparing,
            Some("execution"),
        ),
        (true, "unrelated-turn", ThreadActivityKind::Responding, None),
    ] {
        let mut state = state.clone();
        state.execution.as_mut().unwrap().turn_id = Some(execution_turn.into());
        if !has_attempt {
            state.attempts = Arc::from([]);
            state.model_progress = None;
        }
        let activity = project_activity("thread", &state, None).unwrap();
        assert_eq!(activity.kind, kind);
        assert_eq!(activity.turn_id.as_deref(), Some("turn"));
        assert_eq!(activity.execution_id.as_deref(), execution_id);
        assert_eq!(activity.tools.background, 1);
        if execution_id.is_none() {
            assert_eq!(
                activity.identity,
                ThreadActivity::identity("turn", "attempt", kind)
            );
        }
    }
}

#[test]
fn background_tool_and_question_keep_their_own_activity_without_a_running_turn() {
    let mut state = conflicting_sources();
    state.execution = None;
    state.turns = Arc::from([]);
    let mut projection = ActivityProjection::default();
    for (cancel_requested, kind) in [
        (false, ThreadActivityKind::RunningTool),
        (true, ThreadActivityKind::Stopping),
    ] {
        state.tasks.get_mut("background").unwrap().cancel_requested = cancel_requested;
        let activity = projection.observe("thread", &state).unwrap();
        assert_eq!(activity.turn_id.as_deref(), Some("background-turn"));
        assert_eq!(activity.execution_id, None);
        assert_eq!(activity.kind, kind);
        assert_eq!(activity.tools.count, 1);
        assert_eq!(activity.tools.background, 0);
        assert_eq!(activity.tools.active[0].call_id, "background-call");
    }
    state.tasks.clear();
    let question = projection.observe("thread", &state).unwrap();
    assert_eq!(question.turn_id.as_deref(), Some("question-turn"));
    assert_eq!(question.execution_id, None);
    assert_eq!(question.kind, ThreadActivityKind::AwaitingInput);
    state.interactions.clear();
    assert!(projection.observe("thread", &state).is_none());
}

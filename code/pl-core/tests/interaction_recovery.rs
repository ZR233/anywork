//! Resident decision and input facts remain bounded reads across interaction recovery.
//!
//! These tests pin the close/recovery contract for submitted interactions: closing the runtime
//! resources of a Thread stops models, tools, background tasks and pending permissions, but it is
//! not an answer, a cancellation or a re-ask of an already submitted interaction. Only an explicit
//! resolve or cancel command settles it, and recovery replays neither the question nor execution.

mod support;

use std::collections::BTreeMap;

use pl_core::context::OpaquePayload;
use pl_core::model::DynModelSession;
use pl_core::thread::{
    StepInput, ThreadCheckpoint, ThreadError, ThreadHandle, ThreadSnapshot, ToolDispatch,
    decisions::{
        DecisionRead, DecisionReadLimits, DecisionState, DecisionSummaries, DecisionSummary,
        InputPresenceRead, InteractionDecisionState,
    },
    extensions::ExtensionMutation,
    input::{InputPurpose, ThreadInput},
    interactions::{
        InteractionCancellation, InteractionRecord, InteractionRequest, InteractionResolution,
        InteractionResponse, InteractionState,
    },
    permissions::{PermissionRecord, PermissionState},
};
use pretty_assertions::assert_eq;
use tokio_util::sync::CancellationToken;

use support::{ScriptedModel, text, turn};

fn question(id: &str, turn_id: &str) -> InteractionRequest {
    InteractionRequest {
        id: id.into(),
        turn_id: turn_id.into(),
        payload: OpaquePayload::text(format!("please answer {id}")),
    }
}

#[tokio::test]
async fn closing_the_thread_keeps_a_pending_interaction_recoverable() {
    let (model, _) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("plan-pending".into(), DynModelSession::new(model)).unwrap();
    assert_eq!(
        thread.decision_summaries(DecisionReadLimits {
            rows: 0,
            identity_bytes: 0,
        }),
        DecisionRead::Complete(DecisionSummaries {
            decisions: Vec::new(),
            rows_read: 0,
            identity_bytes: 0,
        }),
    );
    assert_eq!(
        thread.read_input_presence("", 0),
        InputPresenceRead::Absent { rows_read: 0 },
    );
    thread.run_turn(turn("turn-1")).await.unwrap();
    let asked = question("plan-1", "turn-1");
    thread.request_interaction(asked.clone()).await.unwrap();
    let pending = thread
        .snapshot()
        .interactions
        .get("plan-1")
        .cloned()
        .expect("submitted interaction is pending");
    assert!(matches!(pending.state, InteractionState::Pending));
    assert_eq!(pending.revision, 1);

    // Presence scans identities, not these large, unknown-format input bodies. Keep two queued
    // records and one terminal identity so a bounded prefix cannot be mistaken for absence.
    let payload = OpaquePayload::new(
        "application/x-unknown-input",
        u32::MAX,
        "opaque\0 [not json\n".repeat(65_536),
    )
    .unwrap();
    for id in ["input-terminal", "input-head", "input-tail"] {
        thread
            .submit_input(ThreadInput {
                id: id.into(),
                purpose: InputPurpose::Message,
                payload: payload.clone(),
                context: Vec::new(),
            })
            .await
            .unwrap();
    }
    thread.discard_input("input-terminal".into()).await.unwrap();

    thread.close().await.unwrap();

    // Resource close is not an interaction answer: no committed effect cancelled the question.
    for effect in thread.effects().await.unwrap() {
        for record in effect.interactions.iter() {
            if record.request.id == "plan-1" {
                assert_eq!(record.state, InteractionState::Pending);
                assert_eq!(record.revision, 1);
            }
        }
    }

    // The restart DTO keeps the pending question, so the reopened session sees the same fact.
    let checkpoint = serde_json::to_vec(
        &thread
            .checkpoint(thread.snapshot().commit_sequence)
            .unwrap(),
    )
    .unwrap();
    let restored = serde_json::from_slice(&checkpoint).unwrap();
    let resumed =
        ThreadHandle::resume_without_model("plan-pending".into(), Some(restored)).unwrap();
    let record = resumed
        .snapshot()
        .interactions
        .get("plan-1")
        .cloned()
        .expect("recovery preserves the pending interaction");
    assert_eq!(record.request, asked);
    assert_eq!(record.revision, 1);
    assert_eq!(record.state, InteractionState::Pending);

    // Closing resources and restoring the checkpoint preserve the same bounded resident facts.
    for handle in [&thread, &resumed] {
        let identity_bytes =
            std::mem::size_of::<DecisionSummary>() + "plan-1".len() + "turn-1".len();
        assert_eq!(
            handle.decision_summaries(DecisionReadLimits {
                rows: 1,
                identity_bytes,
            }),
            DecisionRead::Complete(DecisionSummaries {
                decisions: vec![DecisionSummary {
                    id: "plan-1".into(),
                    turn_id: "turn-1".into(),
                    revision: 1,
                    state: DecisionState::Interaction(InteractionDecisionState::Pending),
                }],
                rows_read: 1,
                identity_bytes,
            }),
        );
        assert_eq!(
            handle.read_input_presence("input-head", 0),
            InputPresenceRead::LimitExceeded,
        );
        assert_eq!(
            handle.read_input_presence("input-head", 1),
            InputPresenceRead::Known { rows_read: 1 },
        );
        assert_eq!(
            handle.read_input_presence("input-tail", 1),
            InputPresenceRead::LimitExceeded,
        );
        assert_eq!(
            handle.read_input_presence("input-tail", 2),
            InputPresenceRead::Known { rows_read: 2 },
        );
        assert_eq!(
            handle.read_input_presence("input-terminal", 2),
            InputPresenceRead::LimitExceeded,
        );
        assert_eq!(
            handle.read_input_presence("input-terminal", 3),
            InputPresenceRead::Known { rows_read: 3 },
        );
        for missing in ["unknown-input", ""] {
            assert_eq!(
                handle.read_input_presence(missing, 2),
                InputPresenceRead::LimitExceeded,
            );
            assert_eq!(
                handle.read_input_presence(missing, 3),
                InputPresenceRead::Absent { rows_read: 3 },
            );
        }
    }

    // Recovery re-asks nothing and executes nothing. The owner is restored without any model
    // session, so the only facts recovery could commit are its own settlements; asserting that it
    // committed no interaction fact proves the question was neither re-submitted nor answered.
    // Model-backed execution of the resolved continuation is covered by the test below.
    for effect in resumed.effects().await.unwrap() {
        assert!(effect.interactions.is_empty());
    }

    // A replayed submission of the same identity returns the same pending record instead of
    // minting a second question or a new revision.
    let replay = resumed.request_interaction(asked).await.unwrap();
    assert_eq!(replay.revision, 1);
    assert_eq!(replay.state, InteractionState::Pending);
    resumed.close().await.unwrap();
}

#[tokio::test]
async fn a_recovered_interaction_resolves_once_and_repeated_answers_stay_idempotent() {
    let (model, _) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("plan-answer".into(), DynModelSession::new(model)).unwrap();
    thread
        .request_interaction(question("plan-1", "turn-1"))
        .await
        .unwrap();
    thread.close().await.unwrap();
    let checkpoint = serde_json::to_vec(
        &thread
            .checkpoint(thread.snapshot().commit_sequence)
            .unwrap(),
    )
    .unwrap();
    let restored = serde_json::from_slice(&checkpoint).unwrap();
    let (model, seen) = ScriptedModel::new(&[]);
    let resumed = ThreadHandle::resume(
        "plan-answer".into(),
        DynModelSession::new(model),
        Some(restored),
    )
    .unwrap();

    let resolution = InteractionResolution {
        continuation: Some(ThreadInput {
            id: "interaction:plan-1:continuation".into(),
            purpose: InputPurpose::Message,
            payload: OpaquePayload::text("continue with the approved plan"),
            context: vec![text("continue")],
        }),
        id: "plan-1".into(),
        expected_revision: 1,
        response: InteractionResponse {
            payload: OpaquePayload::text("approved"),
            context: vec![text("user approved the plan")],
        },
        mutations: Vec::new(),
    };
    let resolved = resumed
        .resolve_interaction(resolution.clone())
        .await
        .unwrap();
    assert_eq!(resolved.revision, 2);
    // A complete resident read is not a historical decision ledger: the committed resolution
    // leaves the resident map even while its repeatable receipt remains in the effect window.
    assert_eq!(
        resumed.decision_summaries(DecisionReadLimits {
            rows: 0,
            identity_bytes: 0,
        }),
        DecisionRead::Complete(DecisionSummaries {
            decisions: Vec::new(),
            rows_read: 0,
            identity_bytes: 0,
        }),
    );
    let continuation_count = |thread: &ThreadHandle| {
        thread
            .snapshot()
            .inputs
            .iter()
            .filter(|record| record.input.id == "interaction:plan-1:continuation")
            .count()
    };
    assert_eq!(continuation_count(&resumed), 1);

    // The same answer again returns the original receipt without enqueuing a second continuation.
    let repeated = resumed
        .resolve_interaction(resolution.clone())
        .await
        .unwrap();
    assert_eq!(repeated.revision, 2);
    assert_eq!(continuation_count(&resumed), 1);

    // A different answer for the same identity is a conflict, not a second resolution.
    let conflicting = InteractionResolution {
        response: InteractionResponse {
            payload: OpaquePayload::text("revised"),
            context: vec![text("user revised the plan")],
        },
        ..resolution
    };
    assert!(matches!(
        resumed.resolve_interaction(conflicting).await,
        Err(ThreadError::InvalidIdentity)
    ));
    assert_eq!(continuation_count(&resumed), 1);

    // Answering alone starts no model work; the continuation waits for explicit execution.
    assert!(seen.lock().unwrap().is_empty());

    // Explicitly continuing executes the single staged continuation exactly once; the repeated
    // answer above did not enqueue a second input, so exactly one model request follows.
    resumed
        .resume_inputs(pl_core::thread::input::InputDriverOptions {
            max_model_steps: pl_core::thread::ModelStepLimit::Limited(
                3.try_into().expect("nonzero limit"),
            ),
        })
        .await
        .unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(10), async {
        while resumed
            .snapshot()
            .inputs
            .iter()
            .any(|record| record.input.id == "interaction:plan-1:continuation")
        {
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("continuation turn finishes");
    assert_eq!(seen.lock().unwrap().len(), 1);
    resumed.close().await.unwrap();
}

#[tokio::test]
async fn an_explicitly_cancelled_interaction_is_not_resurrected_by_recovery() {
    let (model, _) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("plan-cancelled".into(), DynModelSession::new(model)).unwrap();
    thread
        .request_interaction(question("plan-1", "turn-1"))
        .await
        .unwrap();
    let cancelled = thread
        .cancel_interaction(InteractionCancellation {
            id: "plan-1".into(),
            expected_revision: 1,
        })
        .await
        .unwrap();
    assert_eq!(cancelled.revision, 2);
    assert!(matches!(cancelled.state, InteractionState::Cancelled));
    // The settled record is committed history, so the resident pending map no longer shows it.
    assert!(!thread.snapshot().interactions.contains_key("plan-1"));

    thread.close().await.unwrap();
    let checkpoint = serde_json::to_vec(
        &thread
            .checkpoint(thread.snapshot().commit_sequence)
            .unwrap(),
    )
    .unwrap();
    let restored = serde_json::from_slice(&checkpoint).unwrap();
    let resumed =
        ThreadHandle::resume_without_model("plan-cancelled".into(), Some(restored)).unwrap();
    // Recovery must not rebuild the cancelled interaction from history or accept new answers.
    assert!(!resumed.snapshot().interactions.contains_key("plan-1"));
    assert!(matches!(
        resumed
            .resolve_interaction(InteractionResolution {
                continuation: None,
                id: "plan-1".into(),
                expected_revision: 1,
                response: InteractionResponse {
                    payload: OpaquePayload::text("approved"),
                    context: Vec::new(),
                },
                mutations: Vec::new(),
            })
            .await,
        Err(ThreadError::InvalidIdentity)
    ));
    assert!(matches!(
        resumed
            .cancel_interaction(InteractionCancellation {
                id: "plan-1".into(),
                expected_revision: 2,
            })
            .await,
        Err(ThreadError::InvalidIdentity)
    ));

    // The owner is open again and can ask a genuinely new question.
    let fresh = resumed
        .request_interaction(question("plan-2", "turn-2"))
        .await
        .unwrap();
    assert_eq!(fresh.revision, 1);
    assert!(matches!(fresh.state, InteractionState::Pending));
    resumed.close().await.unwrap();
}

/// Stops inside a pending execution-permission wait exactly like a host approval prompt.
#[derive(Debug)]
struct AwaitingPermission;

impl pl_core::tool::opaque::Tool for AwaitingPermission {
    async fn execute(
        &self,
        _: OpaquePayload,
        context: pl_core::tool::opaque::CallContext,
    ) -> Result<pl_core::tool::ToolOutput, pl_core::tool::opaque::ToolError> {
        let tasks = context.tasks.clone().expect("task access is granted");
        let decision = tasks
            .request_execution_permission(
                OpaquePayload::text("allow this command?"),
                context.cancellation.clone(),
            )
            .await
            .map_err(pl_core::tool::opaque::ToolError::new)?;
        Ok(pl_core::tool::ToolOutput::new(
            OpaquePayload::text(format!("{decision:?}")),
            vec![text("decision recorded")],
        ))
    }
}

#[tokio::test]
async fn close_stops_runtime_resources_while_preserving_the_pending_interaction() {
    let (model, _) = ScriptedModel::new(&["await"]);
    let thread = ThreadHandle::start("plan-resources".into(), DynModelSession::new(model)).unwrap();
    thread
        .register_tools(vec![
            pl_core::tool::opaque::Registration::new(
                "await".into(),
                OpaquePayload::text("await approval"),
                AwaitingPermission,
            )
            .unwrap(),
        ])
        .await
        .unwrap();
    thread
        .step(StepInput {
            turn_id: "approval-turn".into(),
            attempt_id: "approval-attempt".into(),
            content: vec![text("run the awaiting tool")],
            cancellation: CancellationToken::new(),
        })
        .await
        .unwrap();
    let ToolDispatch::Running(task) = thread
        .execute_tool("approval-turn-await".into(), CancellationToken::new())
        .await
        .unwrap()
    else {
        panic!("the awaiting tool must run as a task")
    };
    tokio::time::timeout(std::time::Duration::from_secs(10), async {
        while !thread
            .snapshot()
            .permissions
            .values()
            .any(|record| record.state == pl_core::thread::permissions::PermissionState::Pending)
        {
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("execution permission becomes pending");
    thread
        .request_interaction(question("plan-1", "turn-1"))
        .await
        .unwrap();

    let identity_bytes = 2 * std::mem::size_of::<DecisionSummary>()
        + "plan-1".len()
        + "turn-1".len()
        + "permission:approval-turn-await".len()
        + "approval-turn".len();
    assert_eq!(
        thread.decision_summaries(DecisionReadLimits {
            rows: 2,
            identity_bytes,
        }),
        DecisionRead::Complete(DecisionSummaries {
            decisions: vec![
                DecisionSummary {
                    id: "plan-1".into(),
                    turn_id: "turn-1".into(),
                    revision: 1,
                    state: DecisionState::Interaction(InteractionDecisionState::Pending),
                },
                DecisionSummary {
                    id: "permission:approval-turn-await".into(),
                    turn_id: "approval-turn".into(),
                    revision: 1,
                    state: DecisionState::Permission(PermissionState::Pending),
                },
            ],
            rows_read: 2,
            identity_bytes,
        }),
    );

    // A crash-safe checkpoint taken while the permission is still pending.
    let running_checkpoint = serde_json::to_vec(
        &thread
            .checkpoint(thread.snapshot().commit_sequence)
            .unwrap(),
    )
    .unwrap();

    thread.close().await.unwrap();

    // Close stopped the background task and settled its permission without granting it, while the
    // submitted interaction survived as a pending logical fact.
    let settled = thread.snapshot();
    assert!(
        !settled.permissions.values().any(|record| {
            record.state == pl_core::thread::permissions::PermissionState::Pending
        })
    );
    assert!(
        !settled
            .tasks
            .values()
            .any(|record| { record.status == pl_core::thread::task::TaskStatus::Running })
    );
    let preserved = settled
        .interactions
        .get("plan-1")
        .cloned()
        .expect("close preserves the pending interaction");
    assert_eq!(preserved.state, InteractionState::Pending);
    assert!(
        thread.effects().await.unwrap().iter().any(|effect| {
            effect.permissions.iter().any(|record| {
                record.call_id == "approval-turn-await"
                    && record.state == pl_core::thread::permissions::PermissionState::Cancelled
            })
        }),
        "close settles the pending permission as cancelled"
    );
    drop(task);

    // Recovering the mid-flight checkpoint keeps the same boundary: the permission does not
    // survive as authorization, the task is interrupted, and the interaction stays pending.
    let restored = serde_json::from_slice(&running_checkpoint).unwrap();
    let (model, seen) = ScriptedModel::new(&[]);
    let resumed = ThreadHandle::resume(
        "plan-resources".into(),
        DynModelSession::new(model),
        Some(restored),
    )
    .unwrap();
    let recovered = resumed.snapshot();
    assert!(
        !recovered.permissions.values().any(|record| {
            record.state == pl_core::thread::permissions::PermissionState::Pending
        })
    );
    assert!(
        !recovered
            .tasks
            .values()
            .any(|record| { record.status == pl_core::thread::task::TaskStatus::Running })
    );
    let preserved = recovered
        .interactions
        .get("plan-1")
        .cloned()
        .expect("recovery preserves the pending interaction");
    assert_eq!(preserved.state, InteractionState::Pending);
    assert!(seen.lock().unwrap().is_empty());
    resumed.close().await.unwrap();
}

#[tokio::test]
async fn resident_decision_reads_are_complete_ordered_and_identity_bounded() {
    let payload = OpaquePayload::new(
        "application/x-unknown-decision",
        u32::MAX,
        "opaque\0 [not json\n".repeat(65_536),
    )
    .unwrap();
    let interaction = |id: &str, revision, state| InteractionRecord {
        created_at: 0,
        updated_at: 0,
        continuation_id: Some("continuation-not-an-identity-budget-input".into()),
        request: InteractionRequest {
            id: id.into(),
            turn_id: "轮次/🦀".into(),
            payload: payload.clone(),
        },
        revision,
        state,
        extension_mutations: vec![ExtensionMutation::Put {
            id: "unread-extension".into(),
            expected_revision: None,
            payload: payload.clone(),
        }],
    };
    let permission = |id: &str, state| PermissionRecord {
        created_at: 0,
        updated_at: 0,
        response: Some(payload.clone()),
        id: id.into(),
        task_id: "original-task".into(),
        call_id: "original-call".into(),
        turn_id: "权限/é".into(),
        tool_id: "original-tool".into(),
        revision: 7,
        payload: payload.clone(),
        state,
    };
    // A public checkpoint transfer can carry terminal records before pruning. Restoring this
    // complete envelope exercises the real handle's resident read, not a substitute reader.
    // Deliberately differing map keys and record IDs pin ordering to keys but identity to records.
    let checkpoint = ThreadCheckpoint::capture_transfer(
        "resident-decisions".into(),
        0,
        ThreadSnapshot {
            interactions: BTreeMap::from([
                (
                    "c-pending".into(),
                    interaction("a-待定", 1, InteractionState::Pending),
                ),
                (
                    "a-resolved".into(),
                    interaction(
                        "z-已答",
                        4,
                        InteractionState::Resolved(InteractionResponse {
                            payload: payload.clone(),
                            context: vec![pl_core::context::ContextContent::Opaque {
                                payload: payload.clone(),
                            }],
                        }),
                    ),
                ),
                (
                    "b-cancelled".into(),
                    interaction("m-已取消", 3, InteractionState::Cancelled),
                ),
            ]),
            permissions: BTreeMap::from([
                (
                    "c-cancelled".into(),
                    permission("m-撤销", PermissionState::Cancelled),
                ),
                (
                    "a-denied".into(),
                    permission("z-拒绝", PermissionState::Denied),
                ),
                (
                    "b-allowed".into(),
                    permission("a-允许", PermissionState::Allowed),
                ),
            ]),
            ..ThreadSnapshot::default()
        },
    );
    // Decode the actual recovery envelope, including unknown opaque formats and response bodies.
    let checkpoint = serde_json::from_slice(&serde_json::to_vec(&checkpoint).unwrap()).unwrap();
    let thread =
        ThreadHandle::resume_without_model("resident-decisions".into(), Some(checkpoint)).unwrap();
    let expected = vec![
        DecisionSummary {
            id: "z-已答".into(),
            turn_id: "轮次/🦀".into(),
            revision: 4,
            state: DecisionState::Interaction(InteractionDecisionState::Resolved),
        },
        DecisionSummary {
            id: "m-已取消".into(),
            turn_id: "轮次/🦀".into(),
            revision: 3,
            state: DecisionState::Interaction(InteractionDecisionState::Cancelled),
        },
        DecisionSummary {
            id: "a-待定".into(),
            turn_id: "轮次/🦀".into(),
            revision: 1,
            state: DecisionState::Interaction(InteractionDecisionState::Pending),
        },
        DecisionSummary {
            id: "z-拒绝".into(),
            turn_id: "权限/é".into(),
            revision: 7,
            state: DecisionState::Permission(PermissionState::Denied),
        },
        DecisionSummary {
            id: "a-允许".into(),
            turn_id: "权限/é".into(),
            revision: 7,
            state: DecisionState::Permission(PermissionState::Allowed),
        },
        DecisionSummary {
            id: "m-撤销".into(),
            turn_id: "权限/é".into(),
            revision: 7,
            state: DecisionState::Permission(PermissionState::Cancelled),
        },
    ];
    let rows = expected.len();
    let identity_bytes = rows * std::mem::size_of::<DecisionSummary>()
        + expected
            .iter()
            .map(|summary| summary.id.len() + summary.turn_id.len())
            .sum::<usize>();
    let complete = DecisionRead::Complete(DecisionSummaries {
        decisions: expected,
        rows_read: rows,
        identity_bytes,
    });
    assert_eq!(
        thread.decision_summaries(DecisionReadLimits {
            rows,
            identity_bytes,
        }),
        complete,
        "large opaque prompts, responses, context and mutations do not enter the identity budget",
    );
    for limits in [
        DecisionReadLimits {
            rows: rows - 1,
            identity_bytes,
        },
        DecisionReadLimits {
            rows,
            identity_bytes: identity_bytes - 1,
        },
        DecisionReadLimits {
            rows: 0,
            identity_bytes: usize::MAX,
        },
        DecisionReadLimits {
            rows: usize::MAX,
            identity_bytes: 0,
        },
    ] {
        assert_eq!(
            thread.decision_summaries(limits),
            DecisionRead::LimitExceeded,
            "no partial result for {limits:?}",
        );
    }
    assert_eq!(
        thread.decision_summaries(DecisionReadLimits {
            rows: usize::MAX,
            identity_bytes: usize::MAX,
        }),
        complete,
        "allocation and reported usage depend on resident rows, not the requested maximum",
    );
    thread.close().await.unwrap();
}

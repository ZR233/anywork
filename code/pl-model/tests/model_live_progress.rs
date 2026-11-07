//! Public-API coverage of the live observation produced while a provider stream is still open.
//!
//! The cases drive real fixture SSE through the Thread so they exercise the decoder, the observation
//! producer and the typed port together, and they read the failure receipt through its public reader.

use std::sync::{Arc, Mutex};
use std::time::Duration;

use pl_agent_tool::{Tool, ToolDefinition, ToolHandle};
use pl_core::chat::PresentationPart;
use pl_core::context::{
    ContextContent, ContextRecord, ContextSnapshot, ContextSource, OpaquePayload,
};
use pl_core::model::{
    AggregateChannel, DynModelSession, ModelError, ModelFactory, ModelFailureKind, ModelProgress,
    ModelProgressSender, ModelRequest, ModelSession as CoreModelSession, ObservedPartIdentity,
    PreparedModelCall, ToolCallMode,
};
use pl_core::thread::{ModelStepLimit, ThreadHandle, TurnInput};
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, Registration, ToolError},
};
use pl_model::completion::{
    CompletionPresentationItem, CompletionPresentationItemKind, CompletionPresentationPart,
    CompletionPresentationPartKind, CompletionRequest, Message, MessageContent, MessageRole,
};
use pl_model::model::{ModelInfo, ModelTransportProfile};
use pl_model::protocol::ProtocolEndpoint;
use pl_model::runtime::{
    ModelInvocationContext, ModelRuntime, ModelSession, model_failure_receipt,
    thread_tool_declaration,
};
use pl_protocol::PureError;
use pl_protocol::trace::TraceTextChannel;
use pl_provider_fixture::{FixtureServer, Protocol, Reply, ReplyStage, Step};
use serde_json::{Value, json};

fn model(model_id: &str, profile: ModelTransportProfile) -> ModelInfo {
    let mut model = ModelInfo::compatible(model_id);
    model.binding.set_transport(profile);
    model
}

fn user_turn(prompt: &str) -> TurnInput {
    TurnInput {
        turn_id: "live-turn".into(),
        attempt_prefix: "live-attempt".into(),
        content: vec![ContextContent::Text {
            text: Arc::from(prompt),
        }],
        max_model_steps: ModelStepLimit::Limited(1.try_into().expect("one step is a valid limit")),
        cancellation: Default::default(),
    }
}

fn user_message(text: &str) -> Message {
    Message {
        presentation: Default::default(),
        role: MessageRole::User,
        content: MessageContent::text(text),
        reasoning_content: None,
        tool_calls: None,
        tool_result: None,
        metadata: Default::default(),
    }
}

#[tokio::test]
async fn normalized_part_starts_precede_completion_without_ending_prior_reasoning() {
    use pl_core::model::{ObservedItemKind, ObservedPartKind};
    use tokio_util::sync::CancellationToken;
    let reached = CancellationToken::new();
    let release = CancellationToken::new();
    let reasoning = json!({"id":"reasoning","type":"reasoning","status":"completed",
        "content":[{"type":"reasoning_text","text":"thinking"}],"summary":[]});
    let text = json!({"id":"answer","type":"message","role":"assistant","status":"completed",
        "content":[{"type":"output_text","text":"answer"}]});
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp, "part beginnings", 0, Reply::GatedSse {
            before: vec![
                json!({"type":"response.created","response":{"id":"beginnings","model":"live-fixture"}}),
                json!({"type":"response.output_item.added","output_index":0,
                    "item":{"id":"reasoning","type":"reasoning","summary":[]}}),
                json!({"type":"response.reasoning_text.delta","item_id":"reasoning","content_index":0,"delta":"think"}),
                json!({"type":"response.reasoning_text.delta","item_id":"reasoning","content_index":0,"delta":"ing"}),
                json!({"type":"response.output_text.delta","item_id":"answer","content_index":0,"delta":"an"}),
                json!({"type":"response.output_text.delta","item_id":"answer","content_index":0,"delta":"swer"}),
            ],
            reached: reached.clone(), release: release.clone(),
            after: vec![
                json!({"type":"response.output_item.done","output_index":0,"item":reasoning}),
                json!({"type":"response.output_item.done","output_index":1,"item":text}),
                json!({"type":"response.completed","response":{"id":"beginnings","model":"live-fixture","output":[reasoning,text]}}),
            ],
        },
    )]).await.unwrap();
    let runtime = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::compatible("fixture", fixture.base_url()),
        model("live-fixture", ModelTransportProfile::responses_http()),
    )
    .unwrap();
    let session = ModelFactory::new(pl_model::runtime::ThreadModel::new(runtime, None))
        .open_session()
        .await
        .unwrap();
    let thread = ThreadHandle::start("part-beginnings".into(), session).unwrap();
    let task = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(user_turn("part beginnings")).await })
    };
    let mut subscription = thread.subscribe();
    tokio::time::timeout(Duration::from_secs(10), reached.cancelled())
        .await
        .unwrap();
    let before = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let effects = thread.effects().await.unwrap();
            if effects
                .iter()
                .map(|e| e.model_member_starts.len())
                .sum::<usize>()
                == 2
            {
                break effects;
            }
            subscription.next().await.unwrap();
        }
    })
    .await
    .unwrap();
    assert!(
        before.iter().all(|e| e.model_members.is_empty()),
        "text beginning must not fabricate reasoning completion"
    );
    assert!(
        !thread
            .snapshot()
            .context
            .records
            .iter()
            .any(|r| r.source == ContextSource::Assistant)
    );
    let starts: Vec<_> = before
        .iter()
        .flat_map(|e| e.model_member_starts.iter())
        .collect();
    for (start, id, kind) in [
        (starts[0], "reasoning", ObservedPartKind::ReasoningText),
        (starts[1], "answer", ObservedPartKind::OutputText),
    ] {
        let ObservedPartIdentity::Provider(identity) = &start.identity else {
            panic!("real provider part");
        };
        assert_eq!(identity.item_id.as_ref(), id);
        assert_eq!(identity.part, kind);
        assert_eq!(identity.content_index, 0);
        assert_eq!(
            identity.output_index, None,
            "late metadata does not fabricate an earlier index"
        );
    }
    let ObservedPartIdentity::Provider(reasoning_start) = &starts[0].identity else {
        unreachable!()
    };
    assert_eq!(reasoning_start.item_kind, ObservedItemKind::Reasoning);
    release.cancel();
    tokio::time::timeout(Duration::from_secs(10), task)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    let after = thread.effects().await.unwrap();
    assert_eq!(
        after
            .iter()
            .map(|e| e.model_member_starts.len())
            .sum::<usize>(),
        2,
        "multiple deltas and late final output indices do not repeat starts"
    );
    assert_eq!(
        after.iter().map(|e| e.model_members.len()).sum::<usize>(),
        2
    );
    let last_start = after
        .iter()
        .filter(|e| !e.model_member_starts.is_empty())
        .map(|e| e.sequence)
        .max()
        .unwrap();
    let first_complete = after
        .iter()
        .find(|e| !e.model_members.is_empty())
        .unwrap()
        .sequence;
    assert!(last_start < first_complete);
    thread.close().await.unwrap();
    assert_eq!(fixture.finish().await.unwrap().len(), 1);
}

#[tokio::test]
async fn summary_delta_parts_start_once_before_item_done() {
    exercise_summary_starts(true).await;
}

#[tokio::test]
async fn summary_placeholder_does_not_start_a_part_when_text_begins() {
    exercise_summary_starts(false).await;
}

async fn exercise_summary_starts(with_summary: bool) {
    use pl_core::model::ObservedPartKind;
    use tokio_util::sync::CancellationToken;
    let reached = CancellationToken::new();
    let release = CancellationToken::new();
    let mut before = vec![
        json!({"type":"response.created","response":{"id":"summary-starts","model":"live-fixture"}}),
        json!({"type":"response.output_item.added","output_index":0,
            "item":{"id":"reasoning","type":"reasoning","summary":[]}}),
        json!({"type":"response.reasoning_text.delta","item_id":"reasoning","content_index":0,"delta":"thinking"}),
    ];
    if with_summary {
        // Start index one first: the item-added placeholder must not preempt it with a fake zero.
        for (index, delta) in [(1, "sec"), (1, "ond"), (0, "fir"), (0, "st")] {
            before.push(json!({"type":"response.reasoning_summary_text.delta",
                "item_id":"reasoning","summary_index":index,"delta":delta}));
        }
    }
    before.extend([
        json!({"type":"response.output_text.delta","item_id":"answer","content_index":0,"delta":"an"}),
        json!({"type":"response.output_text.delta","item_id":"answer","content_index":0,"delta":"swer"}),
    ]);
    let summary = if with_summary {
        vec![
            json!({"type":"summary_text","text":"first"}),
            json!({"type":"summary_text","text":"second"}),
        ]
    } else {
        vec![]
    };
    let reasoning = json!({"id":"reasoning","type":"reasoning","status":"completed",
        "content":[{"type":"reasoning_text","text":"thinking"}],"summary":summary});
    let answer = json!({"id":"answer","type":"message","role":"assistant","status":"completed",
        "content":[{"type":"output_text","text":"answer"}]});
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp, "summary beginnings", 0, Reply::GatedSse {
            before, reached: reached.clone(), release: release.clone(),
            after: vec![
                json!({"type":"response.output_item.done","output_index":0,"item":reasoning}),
                json!({"type":"response.output_item.done","output_index":1,"item":answer}),
                json!({"type":"response.completed","response":{"id":"summary-starts","model":"live-fixture","output":[reasoning,answer]}}),
            ],
        },
    )]).await.unwrap();
    let runtime = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::compatible("fixture", fixture.base_url()),
        model("live-fixture", ModelTransportProfile::responses_http()),
    )
    .unwrap();
    let session = ModelFactory::new(pl_model::runtime::ThreadModel::new(runtime, None))
        .open_session()
        .await
        .unwrap();
    let thread = ThreadHandle::start("summary-beginnings".into(), session).unwrap();
    let task = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(user_turn("summary beginnings")).await })
    };
    tokio::time::timeout(Duration::from_secs(10), reached.cancelled())
        .await
        .unwrap();
    let mut subscription = thread.subscribe();
    let prefix = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let effects = thread.effects().await.unwrap();
            if effects
                .iter()
                .flat_map(|e| e.model_member_starts.iter())
                .any(|start| {
                    matches!(&start.identity, ObservedPartIdentity::Provider(p)
                    if p.item_id.as_ref() == "answer")
                })
            {
                break effects;
            }
            subscription.next().await.unwrap();
        }
    })
    .await
    .unwrap();
    let starts: Vec<_> = prefix
        .iter()
        .flat_map(|e| e.model_member_starts.iter())
        .map(|start| {
            let ObservedPartIdentity::Provider(part) = &start.identity else {
                panic!("provider part");
            };
            (part.item_id.as_ref(), part.part, part.content_index)
        })
        .collect();
    let mut expected = vec![("reasoning", ObservedPartKind::ReasoningText, 0)];
    if with_summary {
        expected.extend([
            ("reasoning", ObservedPartKind::SummaryText, 1),
            ("reasoning", ObservedPartKind::SummaryText, 0),
        ]);
    }
    expected.push(("answer", ObservedPartKind::OutputText, 0));
    assert_eq!(
        starts, expected,
        "only actual part deltas may supply summary beginnings"
    );
    assert!(
        prefix.iter().all(|e| e.model_members.is_empty()),
        "text beginning must not fabricate prior reasoning completion"
    );
    let snapshot = thread.snapshot();
    assert_eq!(
        snapshot.attempts.last().unwrap().status,
        pl_core::thread::AttemptStatus::Running
    );
    assert!(snapshot.attempts.last().unwrap().usage.is_none());
    assert!(
        !snapshot
            .context
            .records
            .iter()
            .any(|r| r.source == ContextSource::Assistant)
    );
    release.cancel();
    tokio::time::timeout(Duration::from_secs(10), task)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    let effects = thread.effects().await.unwrap();
    assert_eq!(
        effects
            .iter()
            .map(|e| e.model_member_starts.len())
            .sum::<usize>(),
        expected.len(),
        "later deltas and final items must not duplicate starts"
    );
    assert_eq!(
        effects.iter().map(|e| e.model_members.len()).sum::<usize>(),
        2
    );
    assert!(
        prefix
            .iter()
            .filter(|e| !e.model_member_starts.is_empty())
            .all(|e| e.sequence
                < effects
                    .iter()
                    .find(|e| !e.model_members.is_empty())
                    .unwrap()
                    .sequence)
    );
    thread.close().await.unwrap();
    assert_eq!(fixture.finish().await.unwrap().len(), 1);
}

#[tokio::test]
async fn late_commentary_phase_corrects_text_metadata_without_final_authorization() {
    use pl_core::thread::{AttemptOutcome, TurnOutcome};
    for initial_phase in [None, Some("commentary"), Some("final_answer")] {
        for with_members in [false, true] {
            let mut added =
                json!({"id":"phase-item","type":"message","role":"assistant","content":[]});
            if let Some(phase) = initial_phase {
                added["phase"] = json!(phase);
            }
            let done = json!({"id":"phase-item","type":"message","role":"assistant",
                "phase":"commentary","status":"completed",
                "content":[{"type":"output_text","text":"working"}]});
            let fixture = FixtureServer::start(vec![Step::prompt(
                Protocol::ResponsesHttp, "late phase", 0, Reply::Sse(vec![
                    json!({"type":"response.created","response":{"id":"phase-response","model":"live-fixture"}}),
                    json!({"type":"response.output_item.added","output_index":0,"item":added}),
                    json!({"type":"response.output_text.delta","item_id":"phase-item","content_index":0,"delta":"work"}),
                    json!({"type":"response.output_text.delta","item_id":"phase-item","content_index":0,"delta":"ing"}),
                    json!({"type":"response.output_item.done","output_index":0,"item":done}),
                    json!({"type":"response.completed","response":{"id":"phase-response","model":"live-fixture","output":[done]}}),
                ]),
            )]).await.unwrap();
            let runtime = ModelRuntime::new_with_account_id(
                "fixture",
                ProtocolEndpoint::compatible("fixture", fixture.base_url()),
                model("live-fixture", ModelTransportProfile::responses_http()),
            )
            .unwrap();
            if with_members {
                let session = ModelFactory::new(pl_model::runtime::ThreadModel::new(runtime, None))
                    .open_session()
                    .await
                    .unwrap();
                let thread = ThreadHandle::start("late-phase".into(), session).unwrap();
                let result = thread.run_turn(user_turn("late phase")).await.unwrap();
                assert_eq!(
                    result.outcome,
                    TurnOutcome::StepLimit,
                    "a Text start is not authorization to finish a commentary-only turn"
                );
                let effects = thread.effects().await.unwrap();
                assert_eq!(
                    effects
                        .iter()
                        .map(|e| e.model_member_starts.len())
                        .sum::<usize>(),
                    1
                );
                let members: Vec<_> = effects
                    .iter()
                    .flat_map(|e| e.model_members.iter())
                    .collect();
                assert_eq!(members.len(), 1);
                let receipt = pl_model::runtime::model_member_receipt(members[0]).unwrap();
                assert_eq!(
                    receipt.item.kind,
                    CompletionPresentationItemKind::Text(TraceTextChannel::Commentary)
                );
                assert!(effects.iter().any(|e| matches!(
                    e.attempt.as_ref().map(|a| &a.outcome),
                    Some(AttemptOutcome::Committed(output))
                        if output.turn_action == pl_core::model::ModelTurnAction::Continue
                )));
                thread.close().await.unwrap();
            } else {
                let response = runtime
                    .complete(
                        CompletionRequest::builder()
                            .messages(vec![user_message("late phase")])
                            .build(),
                        ModelInvocationContext::new(ModelSession::default()),
                    )
                    .await
                    .unwrap();
                assert_eq!(response.presentation_items.len(), 1);
                assert_eq!(
                    response.presentation_items[0].kind,
                    CompletionPresentationItemKind::Text(TraceTextChannel::Commentary)
                );
                assert_eq!(response.presentation_items[0].parts[0].text, "working");
            }
            assert_eq!(fixture.finish().await.unwrap().len(), 1);
        }
    }
}

#[tokio::test]
async fn authoritative_member_is_reliable_while_provider_stream_is_still_open() {
    use pl_core::thread::{AttemptOutcome, AttemptStatus};
    use pl_model::runtime::{ModelMemberState, model_member_receipt};

    for (status, expected) in [
        (None, ModelMemberState::Completed),
        (Some("completed"), ModelMemberState::Completed),
        (Some("incomplete"), ModelMemberState::Interrupted),
    ] {
        let mut item = json!({"id":"real-member","type":"message","role":"assistant",
            "content":[{"type":"output_text","text":"authoritative body"}]});
        if let Some(status) = status {
            item["status"] = json!(status);
        }
        let done = json!({"type":"response.output_item.done","output_index":4,"item":item});
        let fixture = FixtureServer::start(vec![Step::prompt(
            Protocol::ResponsesHttp, "reliable member", 0,
            Reply::HangingSse(vec![
                json!({"type":"response.created","response":{"id":"response","model":"live-fixture"}}),
                json!({"type":"response.output_text.delta","item_id":"real-member","output_index":4,
                    "content_index":0,"delta":"untrusted delta"}),
                done.clone(), done,
            ]),
        )]).await.unwrap();
        let runtime = ModelRuntime::new_with_account_id(
            "fixture",
            ProtocolEndpoint::compatible("fixture", fixture.base_url()),
            model("live-fixture", ModelTransportProfile::responses_http()),
        )
        .unwrap();
        let session = ModelFactory::new(pl_model::runtime::ThreadModel::new(runtime, None))
            .open_session()
            .await
            .unwrap();
        let thread = ThreadHandle::start("reliable-thread".into(), session).unwrap();
        let input = user_turn("reliable member");
        let cancellation = input.cancellation.clone();
        let task = {
            let thread = thread.clone();
            tokio::spawn(async move { thread.run_turn(input).await })
        };
        let mut snapshots = thread.subscribe();
        let member = tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                if let Some(member) = thread
                    .effects()
                    .await
                    .unwrap()
                    .iter()
                    .flat_map(|effect| effect.model_members.iter())
                    .next()
                    .cloned()
                {
                    break member;
                }
                snapshots.next().await.unwrap();
            }
        })
        .await
        .expect("member is admitted before attempt completion");
        let receipt = model_member_receipt(&member).unwrap();
        assert_eq!(member.generation, 0);
        assert_eq!(
            member.attempt_id,
            thread.snapshot().attempts.last().unwrap().attempt_id
        );
        assert_eq!(receipt.state, expected);
        assert_eq!(receipt.item.provider_item_id, "real-member");
        assert_eq!(receipt.item.output_index, Some(4));
        assert_eq!(receipt.item.parts[0].content_index, 0);
        assert_eq!(receipt.item.parts[0].text, "authoritative body");
        let snapshot = thread.snapshot();
        assert_eq!(
            snapshot.attempts.last().unwrap().status,
            AttemptStatus::Running
        );
        assert!(snapshot.attempts.last().unwrap().usage.is_none());
        assert!(
            !snapshot
                .context
                .records
                .iter()
                .any(|r| r.source == ContextSource::Assistant)
        );
        cancellation.cancel();
        assert!(matches!(
            tokio::time::timeout(Duration::from_secs(10), task)
                .await
                .unwrap()
                .unwrap(),
            Err(pl_core::thread::ThreadError::Cancelled)
        ));
        let effects = thread.effects().await.unwrap();
        let beginnings: Vec<_> = effects
            .iter()
            .filter(|e| !e.model_member_starts.is_empty())
            .collect();
        assert_eq!(beginnings.len(), 1);
        assert!(
            beginnings[0].sequence
                < effects
                    .iter()
                    .find(|e| !e.model_members.is_empty())
                    .unwrap()
                    .sequence
        );
        assert_eq!(
            effects.iter().map(|e| e.model_members.len()).sum::<usize>(),
            1
        );
        let terminal = effects
            .iter()
            .filter_map(|e| e.attempt.as_ref())
            .next_back()
            .unwrap();
        let AttemptOutcome::Cancelled { result: Err(error) } = &terminal.outcome else {
            panic!("cancelled attempt keeps its producer failure");
        };
        assert_eq!(
            model_failure_receipt(error)
                .unwrap()
                .unwrap()
                .presentation_items,
            vec![receipt.item]
        );
        thread.close().await.unwrap();
        fixture.shutdown().await.unwrap();
    }
}

#[tokio::test]
async fn admitted_member_survives_safe_recovery_after_clean_eof() {
    use pl_core::model::{ModelRecoveryPhase, ObservedPartKind};
    use pl_core::thread::{AttemptOutcome, TurnOutcome};
    use pl_model::runtime::{ModelMemberState, model_member_receipt, model_response_receipt};
    let recovered_item = json!({
        "id":"recovered-answer","type":"message","role":"assistant",
        "content":[{"type":"output_text","text":"successful answer"}]
    });
    let fixture = FixtureServer::start(vec![
        Step::prompt(
            Protocol::ResponsesHttp,
            "recover after EOF",
            0,
            // A clean transport EOF, not a provider error event or a gated stream.
            Reply::Sse(vec![
                json!({"type":"response.created","response":{"id":"response","model":"live-fixture"}}),
                json!({"type":"response.output_item.done","output_index":0,"item":{
                    "id":"irrevocable","type":"reasoning",
                    "summary":[{"type":"summary_text","text":"frozen before EOF"}]}}),
            ]),
        ),
        Step::prompt(
            Protocol::ResponsesHttp,
            "recover after EOF",
            1,
            Reply::Sse(vec![
                json!({"type":"response.created","response":{"id":"recovered","model":"live-fixture"}}),
                json!({"type":"response.output_item.done","output_index":0,"item":recovered_item}),
                json!({"type":"response.completed","response":{
                    "id":"recovered","model":"live-fixture","output":[recovered_item]}}),
            ]),
        ),
    ])
    .await
    .unwrap();
    let runtime = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::compatible("fixture", fixture.base_url()),
        model("live-fixture", ModelTransportProfile::responses_http()),
    )
    .unwrap();
    let session = ModelFactory::new(pl_model::runtime::ThreadModel::new(runtime, None))
        .open_session()
        .await
        .unwrap();
    let thread = ThreadHandle::start("clean-eof-recovery".into(), session).unwrap();
    let result = tokio::time::timeout(
        Duration::from_secs(10),
        thread.run_turn(user_turn("recover after EOF")),
    )
    .await
    .unwrap();
    let effects = thread.effects().await.unwrap();
    let members = effects
        .iter()
        .flat_map(|effect| effect.model_members.iter())
        .collect::<Vec<_>>();
    let beginnings: Vec<_> = effects
        .iter()
        .flat_map(|e| e.model_member_starts.iter())
        .collect();
    // Capture the ungated call before any assertion can hide recovery evidence. Only the local
    // fixture's request metadata is included, never request bodies or account configuration.
    let requests_before_assertions = fixture.recorded();
    let request_metadata: Vec<_> = requests_before_assertions
        .iter()
        .map(|request| {
            (
                &request.method,
                &request.path,
                request.accepted,
                &request.diagnostic,
            )
        })
        .collect();
    let member_effects: Vec<_> = effects
        .iter()
        .filter(|effect| {
            !effect.model_members.is_empty()
                || !effect.model_member_starts.is_empty()
                || effect.attempt.is_some()
        })
        .map(|effect| {
            (
                effect.sequence,
                &effect.model_members,
                &effect.model_member_starts,
                &effect.attempt,
            )
        })
        .collect();
    let failure_receipts: Vec<_> = effects
        .iter()
        .filter_map(|effect| {
            let attempt = effect.attempt.as_ref()?;
            let AttemptOutcome::Failed(error) = &attempt.outcome else {
                return None;
            };
            // Serialize the public reader's complete result, including message, providerFailure
            // and partialProgress.observation (generation/recovery), rather than just the preview.
            Some((
                effect.sequence,
                &attempt.attempt_id,
                model_failure_receipt(error).map(|receipt| serde_json::to_string_pretty(&receipt)),
            ))
        })
        .collect();
    let diagnostic = format!(
        "ungated early EOF: turn_result={result:?}\n\
         fixture_request_count={}; request_metadata={request_metadata:#?}\n\
         effects=(sequence, members, starts, attempt): {member_effects:#?}\n\
         decoded_failure_receipts={failure_receipts:#?}",
        requests_before_assertions.len(),
    );
    let completed = result.unwrap_or_else(|error| panic!("{error:?}\n{diagnostic}"));
    assert_eq!(completed.outcome, TurnOutcome::Completed, "{diagnostic}");
    assert_eq!(completed.model_steps, 1, "{diagnostic}");
    assert!(completed.last_output.tool_calls.is_empty(), "{diagnostic}");
    let snapshot = thread.snapshot();
    // Completed attempts are exported to effects, not retained in the live snapshot.
    let attempt_id = &completed.last_output.attempt_id;
    assert!(
        effects
            .iter()
            .filter_map(|effect| effect.attempt.as_ref())
            .all(|attempt| &attempt.attempt_id == attempt_id && attempt.retry_of.is_none()),
        "{diagnostic}"
    );
    assert_eq!(
        effects
            .iter()
            .filter(|effect| matches!(
                effect.attempt.as_ref().map(|attempt| &attempt.outcome),
                Some(AttemptOutcome::Running)
            ))
            .count(),
        1,
        "{diagnostic}"
    );
    assert_eq!(members.len(), 2, "{diagnostic}");
    assert_eq!(beginnings.len(), 2, "{diagnostic}");
    let mut receipts = Vec::new();
    for (index, generation, id, kind, text, part_kind) in [
        (
            0,
            0,
            "irrevocable",
            CompletionPresentationItemKind::Reasoning,
            "frozen before EOF",
            ObservedPartKind::SummaryText,
        ),
        (
            1,
            1,
            "recovered-answer",
            CompletionPresentationItemKind::Text(TraceTextChannel::Final),
            "successful answer",
            ObservedPartKind::OutputText,
        ),
    ] {
        let member = members[index];
        assert_eq!(member.generation, generation, "{diagnostic}");
        assert_eq!(&member.attempt_id, attempt_id, "{diagnostic}");
        assert_eq!(member.turn_id, "live-turn", "{diagnostic}");
        assert_eq!(member.member_id, id, "{diagnostic}");
        let receipt =
            model_member_receipt(member).unwrap_or_else(|error| panic!("{error:?}\n{diagnostic}"));
        assert_eq!(receipt.state, ModelMemberState::Completed, "{diagnostic}");
        assert_eq!(
            receipt.item,
            CompletionPresentationItem {
                provider_item_id: id.into(),
                output_index: Some(0),
                kind,
                parts: vec![CompletionPresentationPart {
                    content_index: 0,
                    provider_part_id: None,
                    kind: if generation == 0 {
                        CompletionPresentationPartKind::SummaryText
                    } else {
                        CompletionPresentationPartKind::OutputText
                    },
                    text: text.into(),
                }],
            },
            "{diagnostic}"
        );
        let start = beginnings[index];
        assert_eq!(start.generation, generation, "{diagnostic}");
        assert_eq!(start.attempt_id, member.attempt_id, "{diagnostic}");
        assert_eq!(start.turn_id, member.turn_id, "{diagnostic}");
        let ObservedPartIdentity::Provider(identity) = &start.identity else {
            panic!("expected provider start identity\n{diagnostic}");
        };
        assert_eq!(identity.item_id.as_ref(), id, "{diagnostic}");
        assert_eq!(identity.part, part_kind, "{diagnostic}");
        assert_eq!(identity.content_index, 0, "{diagnostic}");
        receipts.push(receipt);
    }
    let terminal = effects
        .iter()
        .filter_map(|effect| effect.attempt.as_ref())
        .next_back()
        .unwrap_or_else(|| panic!("missing terminal attempt\n{diagnostic}"));
    assert_eq!(&terminal.attempt_id, attempt_id, "{diagnostic}");
    let AttemptOutcome::Committed(output) = &terminal.outcome else {
        panic!("safe recovery must commit only the successful generation\n{diagnostic}");
    };
    let response = model_response_receipt(output)
        .unwrap_or_else(|error| panic!("{error:?}\n{diagnostic}"))
        .unwrap_or_else(|| panic!("missing success receipt\n{diagnostic}"))
        .response;
    assert_eq!(
        response.presentation_items,
        vec![receipts[1].item.clone()],
        "{diagnostic}"
    );
    assert_eq!(
        response.content.as_deref(),
        Some("successful answer"),
        "{diagnostic}"
    );
    assert!(response.reasoning_content.is_none(), "{diagnostic}");
    assert_eq!(response.orchestration.transport_attempts, 2, "{diagnostic}");
    assert_eq!(response.observation.generation, 1, "{diagnostic}");
    assert_eq!(response.observation.failed.len(), 1, "{diagnostic}");
    let failed = &response.observation.failed[0];
    assert_eq!(failed.generation, 0, "{diagnostic}");
    assert!(
        failed
            .message
            .contains("provider stream ended before completion"),
        "clean EOF must remain distinguishable from a provider error\n{diagnostic}"
    );
    assert_eq!(
        failed
            .parts
            .iter()
            .map(|part| part.text())
            .collect::<String>(),
        "frozen before EOF",
        "{diagnostic}"
    );
    assert_eq!(
        response.observation.recovery.as_ref().unwrap().phase,
        ModelRecoveryPhase::Recovered,
        "{diagnostic}"
    );
    let assistant_records: Vec<_> = snapshot
        .context
        .records
        .iter()
        .filter(|record| record.source == ContextSource::Assistant)
        .collect();
    assert_eq!(assistant_records.len(), 1, "{diagnostic}");
    assert_eq!(
        assistant_records[0]
            .content
            .iter()
            .filter_map(|content| match content {
                ContextContent::Text { text } => Some(text.as_ref()),
                _ => None,
            })
            .collect::<Vec<_>>(),
        vec!["successful answer"],
        "{diagnostic}"
    );
    assert_eq!(assistant_records[0].content, output.content, "{diagnostic}");
    // The opaque assistant receipt intentionally retains failed display observations. Only its
    // successful replay becomes model input; do not confuse the receipt's diagnostics with input.
    let replay = serde_json::to_string(response.replay.as_ref().unwrap()).unwrap();
    assert!(replay.contains("successful answer"), "{diagnostic}");
    assert!(!replay.contains("frozen before EOF"), "{diagnostic}");
    thread.close().await.unwrap();
    let requests = fixture.finish().await.unwrap_or_else(|error| {
        panic!("only the safe recovery request is expected: {error:?}\n{diagnostic}")
    });
    assert_eq!(requests.len(), 2, "{diagnostic}");
    assert!(
        requests.iter().all(|request| request.accepted),
        "{diagnostic}"
    );
    assert!(requests[0].body["input"].is_array(), "{diagnostic}");
    assert_eq!(
        requests[0].body["input"], requests[1].body["input"],
        "{diagnostic}"
    );
    assert!(
        requests[1].body.get("previous_response_id").is_none(),
        "{diagnostic}"
    );
}

#[tokio::test]
async fn reasoning_raw_and_summary_zero_indices_match_reliable_member_and_final_receipt() {
    use pl_core::thread::AttemptOutcome;
    use pl_model::runtime::{ModelMemberState, model_member_receipt, model_response_receipt};
    let item = json!({
        "id":"reasoning-both", "type":"reasoning", "status":"completed",
        "content":[{"id":"raw-part","type":"reasoning_text","text":"authoritative raw"}],
        "summary":[{"id":"summary-part","type":"summary_text","text":"authoritative summary"}]
    });
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp, "reasoning namespaces", 0,
        Reply::Sse(vec![
            json!({"type":"response.created","response":{"id":"both-response","model":"live-fixture"}}),
            json!({"type":"response.output_item.done","output_index":3,"item":item}),
            json!({"type":"response.completed","response":{
                "id":"both-response","model":"live-fixture","output":[item]}}),
        ]),
    )]).await.unwrap();
    let runtime = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::compatible("fixture", fixture.base_url()),
        model("live-fixture", ModelTransportProfile::responses_http()),
    )
    .unwrap();
    let session = ModelFactory::new(pl_model::runtime::ThreadModel::new(runtime, None))
        .open_session()
        .await
        .unwrap();
    let thread = ThreadHandle::start("reasoning-namespaces".into(), session).unwrap();
    let result = thread.run_turn(user_turn("reasoning namespaces")).await;
    assert!(
        result.is_ok(),
        "both provider arrays have their own valid index zero: {result:?}"
    );
    let effects = thread.effects().await.unwrap();
    let members = effects
        .iter()
        .flat_map(|e| e.model_members.iter())
        .collect::<Vec<_>>();
    assert_eq!(members.len(), 1);
    let receipt = model_member_receipt(members[0]).unwrap();
    assert_eq!(receipt.state, ModelMemberState::Completed);
    assert_eq!(receipt.item.provider_item_id, "reasoning-both");
    assert_eq!(receipt.item.output_index, Some(3));
    let starts: Vec<_> = effects
        .iter()
        .filter(|e| !e.model_member_starts.is_empty())
        .collect();
    assert_eq!(
        starts
            .iter()
            .map(|e| e.model_member_starts.len())
            .sum::<usize>(),
        2
    );
    assert!(starts.iter().all(|e| {
        e.sequence
            < effects
                .iter()
                .find(|e| !e.model_members.is_empty())
                .unwrap()
                .sequence
    }));
    assert_eq!(
        receipt.item.parts,
        vec![
            CompletionPresentationPart {
                content_index: 0,
                provider_part_id: Some("raw-part".into()),
                kind: CompletionPresentationPartKind::ReasoningText,
                text: "authoritative raw".into(),
            },
            CompletionPresentationPart {
                content_index: 0,
                provider_part_id: Some("summary-part".into()),
                kind: CompletionPresentationPartKind::SummaryText,
                text: "authoritative summary".into(),
            },
        ]
    );
    let terminal = effects
        .iter()
        .filter_map(|e| e.attempt.as_ref())
        .next_back()
        .unwrap();
    let AttemptOutcome::Committed(output) = &terminal.outcome else {
        panic!("valid raw and summary parts must commit the final canonical response");
    };
    assert_eq!(
        model_response_receipt(output)
            .unwrap()
            .unwrap()
            .response
            .presentation_items,
        vec![receipt.item]
    );
    thread.close().await.unwrap();
    assert_eq!(fixture.finish().await.unwrap().len(), 1);
}

/// Runs one hanging fixture stream through a Thread and returns the first live snapshot the predicate
/// accepts, so the observation is read while the provider stream is still open.
async fn observed_progress(
    prompt: &str,
    protocol: Protocol,
    profile: ModelTransportProfile,
    events: Vec<Value>,
    accept: impl Fn(&ModelProgress) -> bool,
) -> ModelProgress {
    let fixture = FixtureServer::start(vec![Step::prompt(
        protocol,
        prompt,
        0,
        Reply::HangingSse(events),
    )])
    .await
    .expect("fixture starts");
    let runtime = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::compatible("fixture", fixture.base_url()),
        model("live-fixture", profile),
    )
    .expect("fixture endpoint is valid");
    let session = ModelFactory::new(pl_model::runtime::ThreadModel::new(runtime, None))
        .open_session()
        .await
        .expect("model session opens");
    let thread = ThreadHandle::start("live-thread".into(), session).expect("thread starts");
    let progress = {
        let mut subscription = thread.subscribe();
        let turn = thread.run_turn(user_turn(prompt));
        tokio::pin!(turn);
        let observed = tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                let snapshot = tokio::select! {
                    _ = &mut turn => panic!("the turn ended before the live observation arrived"),
                    snapshot = subscription.next() => snapshot.expect("thread stays open"),
                };
                if let Some(active) = snapshot.model_progress.as_ref()
                    && accept(&active.progress)
                {
                    break active.progress.clone();
                }
            }
        })
        .await
        .expect("live observation arrives before the stream ends");
        // The provider stream never completes, so it ends without a terminal event once the fixture
        // stops; bound the wait instead of depending on retry timing.
        let _ = fixture.shutdown().await;
        let _ = tokio::time::timeout(Duration::from_secs(10), turn).await;
        observed
    };
    // The pinned turn future was dropped with its scope, so its borrow of the Thread is gone and the
    // handle can be released here.
    drop(thread);
    progress
}

/// One reasoning item that closes, then two text blocks in the same channel that keep streaming.
fn reasoning_then_same_channel_text_blocks() -> Vec<Value> {
    vec![
        json!({"type":"response.created","response":{"id":"live-stream","model":"live-fixture"}}),
        json!({"type":"response.output_item.added","output_index":0,
            "item":{"id":"reasoning-1","type":"reasoning","summary":[]}}),
        json!({"type":"response.reasoning_summary_text.delta","item_id":"reasoning-1",
            "output_index":0,"summary_index":0,"delta":"ponder"}),
        json!({"type":"response.output_item.done","output_index":0,
            "item":{"id":"reasoning-1","type":"reasoning",
                "summary":[{"type":"summary_text","text":"ponder"}]}}),
        json!({"type":"response.output_item.added","output_index":1,
            "item":{"id":"message-1","type":"message","role":"assistant","phase":"final_answer","content":[]}}),
        json!({"type":"response.output_text.delta","item_id":"message-1",
            "output_index":1,"content_index":0,"delta":"answer"}),
        json!({"type":"response.output_item.added","output_index":2,
            "item":{"id":"message-2","type":"message","role":"assistant","phase":"final_answer","content":[]}}),
        json!({"type":"response.output_text.delta","item_id":"message-2",
            "output_index":2,"content_index":0,"delta":"again"}),
    ]
}

#[tokio::test]
async fn a_closed_item_does_not_freeze_later_blocks_of_the_same_channel() {
    let progress = observed_progress(
        "live prompt",
        Protocol::ResponsesHttp,
        ModelTransportProfile::responses_http(),
        reasoning_then_same_channel_text_blocks(),
        |progress| progress.parts().iter().any(|part| part.text() == "again"),
    )
    .await;

    assert_eq!(
        progress
            .observed_part("reasoning-1", PresentationPart::SummaryText(0))
            .expect("the reasoning item is observed")
            .text(),
        "ponder"
    );
    assert_eq!(
        progress
            .observed_part("message-1", PresentationPart::OutputText(0))
            .expect("the text block that opened after the reasoning item closed")
            .text(),
        "answer"
    );
    assert_eq!(
        progress
            .observed_part("message-2", PresentationPart::OutputText(0))
            .expect("a second block of the same channel stays its own identity")
            .text(),
        "again"
    );
    // Real provider item boundaries replaced the aggregate, so no channel body is kept alongside it.
    assert!(progress.channel(AggregateChannel::Text).is_none());
    assert!(progress.channel(AggregateChannel::Reasoning).is_none());
}

/// One stable text part that grows, plus a later part of its own identity.
fn text_growth_then_a_new_part() -> Vec<Value> {
    vec![
        json!({"type":"response.created","response":{"id":"live-stream","model":"live-fixture"}}),
        json!({"type":"response.output_item.added","output_index":0,
            "item":{"id":"message-1","type":"message","role":"assistant","phase":"final_answer","content":[]}}),
        json!({"type":"response.output_text.delta","item_id":"message-1",
            "output_index":0,"content_index":0,"delta":"a"}),
        json!({"type":"response.output_text.delta","item_id":"message-1",
            "output_index":0,"content_index":0,"delta":"b"}),
        json!({"type":"response.output_item.added","output_index":1,
            "item":{"id":"message-2","type":"message","role":"assistant","phase":"final_answer","content":[]}}),
        json!({"type":"response.output_text.delta","item_id":"message-2",
            "output_index":1,"content_index":0,"delta":"c"}),
    ]
}

/// One part that grows, then enough further parts that the first part stops being the growing tail
/// before it grows again.
fn text_growth_across_a_chunk_boundary() -> Vec<Value> {
    let mut events = vec![
        json!({"type":"response.created","response":{"id":"live-stream","model":"live-fixture"}}),
        json!({"type":"response.output_item.added","output_index":0,
            "item":{"id":"message-1","type":"message","role":"assistant","phase":"final_answer","content":[]}}),
        json!({"type":"response.output_text.delta","item_id":"message-1",
            "output_index":0,"content_index":0,"delta":"a"}),
    ];
    // More parts than one shared chunk, so `message-1` leaves the growing tail.
    for index in 0..66_u32 {
        let item = format!("filler-{index}");
        events.push(json!({"type":"response.output_item.added","output_index": index + 1,
            "item":{"id":item.clone(),"type":"message","role":"assistant","phase":"final_answer","content":[]}}));
        events.push(json!({"type":"response.output_text.delta","item_id":item,
            "output_index": index + 1,"content_index":0,"delta":"x"}));
    }
    events.push(
        json!({"type":"response.output_text.delta","item_id":"message-1",
        "output_index":0,"content_index":0,"delta":"b"}),
    );
    events.push(json!({"type":"response.output_item.added","output_index":67,
        "item":{"id":"message-2","type":"message","role":"assistant","phase":"final_answer","content":[]}}));
    events.push(
        json!({"type":"response.output_text.delta","item_id":"message-2",
        "output_index":67,"content_index":0,"delta":"c"}),
    );
    events
}

#[tokio::test]
async fn a_held_snapshot_stays_immutable_while_the_same_part_keeps_growing() {
    // A consumer that cloned one frame must keep exactly that frame even though the producer keeps
    // appending to the same identity and then opens a new one. The producer edits the shared part
    // list in place only while the watch owns its only reference; holding this clone is what forces
    // the copy-on-write that keeps the delivered frame intact.
    let held_stage = ReplyStage::new();
    let grown_stage = ReplyStage::new();
    let mut prefix = text_growth_then_a_new_part();
    let growth = prefix.split_off(3);
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "live prompt",
        0,
        ReplyStage::staged(vec![prefix, growth, vec![]], &[&held_stage, &grown_stage]),
    )])
    .await
    .expect("fixture starts");
    let runtime = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::compatible("fixture", fixture.base_url()),
        model("live-fixture", ModelTransportProfile::responses_http()),
    )
    .expect("fixture endpoint is valid");
    let session = ModelFactory::new(pl_model::runtime::ThreadModel::new(runtime, None))
        .open_session()
        .await
        .expect("model session opens");
    let thread = ThreadHandle::start("live-thread".into(), session).expect("thread starts");
    let mut subscription = thread.subscribe();
    let turn = thread.run_turn(user_turn("live prompt"));
    tokio::pin!(turn);
    let (held, grown) = tokio::time::timeout(Duration::from_secs(10), async {
        let mut held: Option<ModelProgress> = None;
        loop {
            let snapshot = tokio::select! {
                _ = &mut turn => panic!("the turn ended before both observations arrived"),
                snapshot = subscription.next() => snapshot.expect("thread stays open"),
            };
            let Some(active) = snapshot.model_progress.as_ref() else {
                continue;
            };
            let progress = &active.progress;
            let part = |item: &str| {
                progress
                    .observed_part(item, PresentationPart::OutputText(0))
                    .map(|part| part.text())
            };
            if held.is_none() && part("message-1").as_deref() == Some("a") {
                // The coalescing watch must deliver this frame before growth is released.
                held = Some(progress.clone());
                held_stage.release();
            }
            if let Some(frame) = held.as_ref()
                && part("message-1").as_deref() == Some("ab")
                && part("message-2").as_deref() == Some("c")
            {
                let frames = (frame.clone(), progress.clone());
                grown_stage.release();
                break frames;
            }
        }
    })
    .await
    .expect("both observations arrive before the stream ends");
    // This deliberately live reply has no terminal response: close its owner instead of relying
    // on provider shutdown to settle the turn. Both joins share the original cleanup deadline.
    tokio::time::timeout(Duration::from_secs(10), async {
        thread.close().await.expect("the observation owner closes");
        let _ = turn.await;
    })
    .await
    .expect("the observed thread and turn close");
    fixture.shutdown().await.expect("fixture shuts down");

    // The frame the consumer kept is byte-for-byte the one it saw: the same identity kept streaming
    // after it, but appending to a shared list never mutates a snapshot a consumer already holds.
    assert_eq!(
        held.observed_part("message-1", PresentationPart::OutputText(0))
            .expect("the held frame kept the part it delivered")
            .text(),
        "a"
    );
    assert!(
        held.observed_part("message-2", PresentationPart::OutputText(0))
            .is_none(),
        "a part opened after the held frame is not grafted onto it"
    );
    // The newest frame carries the appended bytes and the new part under their stable identities.
    assert_eq!(
        grown
            .observed_part("message-1", PresentationPart::OutputText(0))
            .expect("the same identity keeps growing")
            .text(),
        "ab"
    );
    assert_eq!(
        grown
            .observed_part("message-2", PresentationPart::OutputText(0))
            .expect("the part opened later has its own identity")
            .text(),
        "c"
    );
}

#[tokio::test]
async fn a_held_snapshot_survives_the_growth_of_a_chunk_it_shared() {
    // The part list is shared in chunks, so the frame a consumer holds keeps exactly what it saw
    // even after the chunk it shared has filled, become an immutable chunk, and been edited again by
    // a later delta on the same identity. The producer only ever reproduces the chunk it edits.
    let held_stage = ReplyStage::new();
    let grown_stage = ReplyStage::new();
    let mut prefix = text_growth_across_a_chunk_boundary();
    let growth = prefix.split_off(3);
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "live prompt",
        0,
        ReplyStage::staged(vec![prefix, growth, vec![]], &[&held_stage, &grown_stage]),
    )])
    .await
    .expect("fixture starts");
    let runtime = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::compatible("fixture", fixture.base_url()),
        model("live-fixture", ModelTransportProfile::responses_http()),
    )
    .expect("fixture endpoint is valid");
    let session = ModelFactory::new(pl_model::runtime::ThreadModel::new(runtime, None))
        .open_session()
        .await
        .expect("model session opens");
    let thread = ThreadHandle::start("live-thread".into(), session).expect("thread starts");
    let mut subscription = thread.subscribe();
    let turn = thread.run_turn(user_turn("live prompt"));
    tokio::pin!(turn);
    let (held, grown) = tokio::time::timeout(Duration::from_secs(10), async {
        let mut held: Option<ModelProgress> = None;
        loop {
            let snapshot = tokio::select! {
                _ = &mut turn => panic!("the turn ended before both observations arrived"),
                snapshot = subscription.next() => snapshot.expect("thread stays open"),
            };
            let Some(active) = snapshot.model_progress.as_ref() else {
                continue;
            };
            let progress = &active.progress;
            let part = |item: &str| {
                progress
                    .observed_part(item, PresentationPart::OutputText(0))
                    .map(|part| part.text())
            };
            if held.is_none() && part("message-1").as_deref() == Some("a") {
                // Hold this frame while it still shares the chunk the producer keeps editing.
                held = Some(progress.clone());
                held_stage.release();
            }
            if let Some(frame) = held.as_ref()
                && part("message-1").as_deref() == Some("ab")
                && part("message-2").as_deref() == Some("c")
            {
                let frames = (frame.clone(), progress.clone());
                grown_stage.release();
                break frames;
            }
        }
    })
    .await
    .expect("both observations arrive before the stream ends");
    // This deliberately live reply has no terminal response: close its owner instead of relying
    // on provider shutdown to settle the turn. Both joins share the original cleanup deadline.
    tokio::time::timeout(Duration::from_secs(10), async {
        thread.close().await.expect("the observation owner closes");
        let _ = turn.await;
    })
    .await
    .expect("the observed thread and turn close");
    fixture.shutdown().await.expect("fixture shuts down");

    // The frame the consumer kept is exactly the one it saw, even though a later delta edited the
    // chunk it shared with the newest snapshot.
    assert_eq!(
        held.observed_part("message-1", PresentationPart::OutputText(0))
            .expect("the held frame kept the part it delivered")
            .text(),
        "a"
    );
    assert!(
        held.observed_part("message-2", PresentationPart::OutputText(0))
            .is_none(),
        "a part opened after the held frame is not grafted onto it"
    );
    assert!(
        held.len() < grown.len(),
        "the frame was held before the list finished growing ({} vs {})",
        held.len(),
        grown.len()
    );
    // The newest frame carries the appended bytes, every part in between, and the new part.
    assert!(
        grown.len() >= 68,
        "one observation per provider item is still observed ({})",
        grown.len()
    );
    assert_eq!(
        grown
            .observed_part("filler-65", PresentationPart::OutputText(0))
            .expect("the part opened after the held frame is still observed")
            .text(),
        "x"
    );
    assert_eq!(
        grown
            .observed_part("message-1", PresentationPart::OutputText(0))
            .expect("the same identity keeps growing")
            .text(),
        "ab"
    );
    assert_eq!(
        grown
            .observed_part("message-2", PresentationPart::OutputText(0))
            .expect("the part opened later has its own identity")
            .text(),
        "c"
    );
}

#[tokio::test]
async fn multiple_summary_indices_of_one_item_stay_distinct_parts() {
    // Two summaries of one reasoning item arrive before it closes, so the `summary_index` the
    // provider reported must already be the part identity: a regression that folds every summary
    // into `SummaryText(0)` would hide the second part until the terminal item rewrote it.
    let events = vec![
        json!({"type":"response.created","response":{"id":"live-stream","model":"live-fixture"}}),
        json!({"type":"response.output_item.added","output_index":0,
            "item":{"id":"reasoning-1","type":"reasoning","summary":[]}}),
        json!({"type":"response.reasoning_summary_text.delta","item_id":"reasoning-1",
            "output_index":0,"summary_index":0,"delta":"first"}),
        json!({"type":"response.reasoning_summary_text.delta","item_id":"reasoning-1",
            "output_index":0,"summary_index":1,"delta":"second"}),
        json!({"type":"response.output_item.added","output_index":1,
            "item":{"id":"message-1","type":"message","role":"assistant","phase":"final_answer","content":[]}}),
        json!({"type":"response.output_text.delta","item_id":"message-1",
            "output_index":1,"content_index":0,"delta":"answer"}),
    ];
    let progress = observed_progress(
        "multi summary",
        Protocol::ResponsesHttp,
        ModelTransportProfile::responses_http(),
        events,
        |progress| {
            progress
                .observed_part("reasoning-1", PresentationPart::SummaryText(1))
                .is_some()
        },
    )
    .await;

    assert_eq!(
        progress
            .observed_part("reasoning-1", PresentationPart::SummaryText(0))
            .expect("the first summary keeps its own index")
            .text(),
        "first"
    );
    assert_eq!(
        progress
            .observed_part("reasoning-1", PresentationPart::SummaryText(1))
            .expect("the second summary is its own part, not folded into index zero")
            .text(),
        "second"
    );
}

#[tokio::test]
async fn reasoning_delta_without_item_id_resolves_the_announced_output_index() {
    let events = vec![
        json!({"type":"response.created","response":{"id":"live-stream","model":"live-fixture"}}),
        json!({"type":"response.output_item.added","output_index":1,
            "item":{"id":"reasoning-1","type":"reasoning","summary":[]}}),
        // No `item_id`: the identity is the item the `output_index` was announced for.
        json!({"type":"response.reasoning_text.delta","output_index":1,
            "content_index":0,"delta":"ponder"}),
        json!({"type":"response.output_item.added","output_index":2,
            "item":{"id":"message-2","type":"message","role":"assistant","phase":"final_answer","content":[]}}),
        json!({"type":"response.output_text.delta","item_id":"message-2",
            "output_index":2,"content_index":0,"delta":"answer"}),
    ];
    let progress = observed_progress(
        "raw reasoning",
        Protocol::ResponsesHttp,
        ModelTransportProfile::responses_http(),
        events,
        |progress| {
            progress
                .observed_part("message-2", PresentationPart::OutputText(0))
                .is_some()
        },
    )
    .await;

    assert_eq!(
        progress
            .observed_part("reasoning-1", PresentationPart::ReasoningText(0))
            .expect("the announced item owns the reasoning delta that omitted its id")
            .text(),
        "ponder"
    );
    assert_eq!(
        progress
            .observed_part("message-2", PresentationPart::OutputText(0))
            .expect("the answer keeps its own identity")
            .text(),
        "answer"
    );
    // Raw reasoning is a provider part of its own; it is neither a summary nor an aggregate.
    assert!(
        progress
            .observed_part("reasoning-1", PresentationPart::SummaryText(0))
            .is_none()
    );
    assert!(progress.channel(AggregateChannel::Reasoning).is_none());
}

#[tokio::test]
async fn chat_reasoning_content_streams_before_the_answer_as_its_own_channel() {
    let events = vec![
        json!({"choices":[{"delta":{"reasoning_content":"ponder"}}]}),
        json!({"choices":[{"delta":{"content":"answer"}}]}),
    ];
    let progress = observed_progress(
        "chat thinking",
        Protocol::Chat,
        ModelTransportProfile::chat_completions_http(),
        events,
        |progress| progress.channel(AggregateChannel::Text).is_some(),
    )
    .await;

    assert_eq!(
        progress
            .channel(AggregateChannel::Reasoning)
            .expect("chat reasoning content is observed as the raw reasoning channel")
            .text(),
        "ponder"
    );
    assert_eq!(
        progress
            .channel(AggregateChannel::Text)
            .expect("the answer is observed on its own channel")
            .text(),
        "answer"
    );
    // Chat reports no provider item identity, so no fabricated provider item stands in for it.
    assert!(
        progress
            .parts()
            .iter()
            .all(|part| matches!(part.identity(), ObservedPartIdentity::Aggregate { .. }))
    );
}

#[tokio::test]
async fn reasoning_delta_without_any_identity_fails_instead_of_inventing_an_item() {
    for (delta, expected) in [
        (
            json!({"type":"response.reasoning_text.delta","content_index":0,"delta":"ponder"}),
            "no item id",
        ),
        (
            json!({"type":"response.reasoning_summary_text.delta","summary_index":3,"delta":"ponder"}),
            "no item id",
        ),
        (
            json!({"type":"response.reasoning_summary_text.delta","item_id":"reasoning","delta":"ponder"}),
            "no valid summary index",
        ),
        (
            json!({"type":"response.reasoning_summary_text.delta","item_id":"reasoning","summary_index":-1,"delta":"ponder"}),
            "no valid summary index",
        ),
    ] {
        let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "unidentified reasoning",
        0,
        Reply::Sse(vec![
            json!({"type":"response.created","response":{"id":"live-stream","model":"live-fixture"}}),
            delta,
        ]),
    )])
    .await
    .expect("fixture starts");
        let runtime = ModelRuntime::new_with_account_id(
            "fixture",
            ProtocolEndpoint::compatible("fixture", fixture.base_url()),
            model("live-fixture", ModelTransportProfile::responses_http()),
        )
        .expect("fixture endpoint is valid");
        let failure = runtime
            .complete(
                CompletionRequest::builder()
                    .messages(vec![user_message("unidentified reasoning")])
                    .build(),
                ModelInvocationContext::new(ModelSession::default()),
            )
            .await
            .expect_err("an unassociable reasoning delta fails instead of fabricating an item");
        assert!(
            failure.to_string().contains("protocol error"),
            "unexpected failure: {failure}"
        );
        assert!(
            failure.to_string().contains(expected),
            "unexpected failure: {failure}"
        );
        let _ = fixture.shutdown().await;
    }
}

fn legacy_binding() -> Value {
    json!({
        "providerInstanceId": "fixture",
        "requestedModel": "fixture-model",
        "adapter": "openAiCompatible",
        "protocol": "responses",
        "isolation": "fixture",
        "purpose": "turn",
    })
}

#[tokio::test]
async fn a_provider_failure_withdraws_the_live_pair_before_the_attempt_returns() {
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::Chat,
        "failed live pair",
        0,
        Reply::PacedEvents {
            initial_delay_ms: 0,
            step_millis: 200,
            events: vec![
                json!({"id":"chat-fail","model":"live-fixture","choices":[{"delta":{"content":"partial"},"finish_reason":null}]}),
                json!({"id":"chat-fail","model":"live-fixture","choices":[],"usage":{"prompt_tokens":1,"completion_tokens":7}}),
                json!({"type":"error","error":{"code":"invalid_request_error","message":"provider failed mid stream"}}),
            ],
        },
    )])
    .await
    .expect("fixture starts");
    let runtime = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::compatible("fixture", fixture.base_url()),
        model(
            "live-fixture",
            ModelTransportProfile::chat_completions_http(),
        ),
    )
    .expect("fixture endpoint is valid");
    let sender = ModelProgressSender::detached(1 << 20);
    sender.publish(ModelProgress::live("failed-turn", "failed-attempt"));
    let request = ModelRequest {
        progress: Some(sender.clone()),
        members: None,
        thread_id: "failed-thread".into(),
        turn_id: "failed-turn".into(),
        attempt_id: "failed-attempt".into(),
        context: ContextSnapshot {
            revision: 1,
            records: vec![ContextRecord {
                id: "failed-input".into(),
                turn_id: Some("failed-turn".into()),
                source: ContextSource::User,
                content: vec![ContextContent::Text {
                    text: "failed live pair".into(),
                }],
                tool_calls: vec![],
            }]
            .into(),
        },
        tools: Default::default(),
        tool_call_mode: ToolCallMode::Sequential,
        solo_tool_ids: Default::default(),
        committed_private_context: None,
        resources: None,
        cancellation: Default::default(),
    };
    let mut session = ModelFactory::new(pl_model::runtime::ThreadModel::new(runtime, None))
        .open_session()
        .await
        .expect("model session opens");
    let call = session
        .prepare(request)
        .await
        .expect("the fixture request prepares");
    let running = tokio::spawn(async move { call.execute().await });
    // 失败之前的成对样本必须真的出现过：等到 provider 已报告输出词元并已发布响应耗时。
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let complete = sender.latest().usage_observation().is_some_and(|usage| {
                usage.completion_tokens == Some(7) && usage.response_millis.is_some()
            });
            if complete {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .expect("the partial pair is observable before the failure");

    let error = tokio::time::timeout(Duration::from_secs(10), running)
        .await
        .expect("the failure arrives")
        .expect("the call task joins")
        .expect_err("the provider fails mid stream");
    let receipt = model_failure_receipt(&error)
        .expect("the receipt decodes")
        .expect("the failure carries a receipt");
    let partial = receipt
        .partial_progress
        .expect("the receipt keeps the partial observation");
    assert!(
        partial.parts().iter().any(|part| part.text() == "partial"),
        "已收到的内容必须保留"
    );
    // 失败收据只承载内容（live usage 不跨序列化边界），因此速度不可用性在同一 live 通道上确认：
    // 失败之后该代次的 pair 整组撤销，而不是「失败前词元 + 失败时钟」。
    let withdrawn = sender.latest();
    let live = withdrawn
        .usage_observation()
        .expect("the live observation identity is retained");
    assert_eq!(
        live.completion_tokens, None,
        "failure must not publish the pre-failure token count as a speed numerator"
    );
    assert_eq!(
        live.response_millis, None,
        "failure must not publish its terminal clock as a speed denominator"
    );
    assert!(
        withdrawn
            .parts()
            .iter()
            .any(|part| part.text() == "partial"),
        "撤销用量不得丢弃已收到的内容"
    );
    // 失败之后到达的在途观察也不能复活这一代次的 pair。
    sender.observe_usage(Some(9), None);
    sender.observe_response_millis(9_999);
    let latest = sender.latest();
    let live = latest
        .usage_observation()
        .expect("the live observation identity is retained");
    assert_eq!(live.completion_tokens, None);
    assert_eq!(live.response_millis, None);
    // 最终 accounting 仍保留 provider 报告的输出词元。
    assert_eq!(error.usage.output_tokens, Some(7));
    let _ = fixture.finish().await;
}

fn legacy_receipt(partial_progress: Value) -> ModelError {
    let payload = json!({
        "message": "provider failed mid stream",
        "binding": legacy_binding(),
        "accounting": serde_json::to_value(pl_protocol::InferenceAccounting::default())
            .expect("default accounting encodes"),
        "partialProgress": partial_progress,
    });
    ModelError {
        details: Some(Box::new(
            pl_model::runtime::migration::migrate_payload(
                &OpaquePayload::new(
                    "pl.model.failure",
                    1,
                    serde_json::to_string(&payload).expect("legacy receipt encodes"),
                )
                .expect("static format and version are valid"),
            )
            .expect("explicit migration succeeds")
            .expect("old payload upgraded"),
        )),
        kind: ModelFailureKind::Unavailable,
        usage: Default::default(),
        source: None,
    }
}

#[test]
fn legacy_failure_receipt_keeps_the_partial_text_it_had_already_received() {
    let item = CompletionPresentationItem {
        provider_item_id: "message-1".into(),
        output_index: Some(0),
        kind: CompletionPresentationItemKind::Text(TraceTextChannel::Final),
        parts: vec![CompletionPresentationPart {
            content_index: 0,
            provider_part_id: None,
            kind: CompletionPresentationPartKind::OutputText,
            text: "received answer".into(),
        }],
    };
    let error = legacy_receipt(json!({
        "content": [],
        "reasoning": null,
        "presentation": [{
            "format": "pl.model.presentation-item",
            "version": 1,
            "content": serde_json::to_string(&item).expect("item encodes"),
        }],
    }));

    let receipt = pl_model::runtime::model_failure_receipt(&error)
        .expect("a version 1 receipt is migrated, not rejected")
        .expect("the receipt is present");
    assert_eq!(receipt.message, "provider failed mid stream");
    let progress = receipt
        .partial_progress
        .expect("the migrated receipt keeps its partial observation");
    assert_eq!(
        progress
            .observed_part("message-1", PresentationPart::OutputText(0))
            .expect("the encoder's item identity is preserved")
            .text(),
        "received answer"
    );
}

#[test]
fn legacy_failure_receipt_recovers_the_channel_aggregate_body() {
    let error = legacy_receipt(json!({
        "content": [{"kind": "text", "text": "half an answer"}],
        "reasoning": {"format": "text/plain", "version": 1, "content": "half a thought"},
        "presentation": [],
    }));

    let receipt = pl_model::runtime::model_failure_receipt(&error)
        .expect("a version 1 receipt is migrated, not rejected")
        .expect("the receipt is present");
    let progress = receipt
        .partial_progress
        .expect("the migrated receipt keeps its partial observation");
    assert_eq!(
        progress
            .channel(AggregateChannel::Text)
            .expect("the received answer text is recovered")
            .text(),
        "half an answer"
    );
    assert_eq!(
        progress
            .channel(AggregateChannel::Reasoning)
            .expect("the received reasoning text is recovered")
            .text(),
        "half a thought"
    );
}

#[test]
fn unknown_failure_receipt_versions_are_still_rejected() {
    let mut error = legacy_receipt(json!({"content": [], "reasoning": null, "presentation": []}));
    error.details = Some(Box::new(
        OpaquePayload::new("pl.model.failure", 99, "{}").expect("valid payload"),
    ));
    let rejected = pl_model::runtime::model_failure_receipt(&error);
    assert!(matches!(
        rejected,
        Err(ModelError {
            kind: ModelFailureKind::UnsupportedContent,
            ..
        })
    ));
}

/// Minimal reliable backend that funds only `limit` bytes of one in-flight call's live output.
///
/// Admission and durability always succeed: the only thing under test is the reservation the real
/// adapter charges against, so the stream has to stop where the quota does and nowhere else.
#[derive(Debug, Default)]
struct OutputQuotaStore {
    limit: u64,
    charges: Arc<Mutex<Vec<u64>>>,
}

impl pl_core::thread::cold::ColdStore for OutputQuotaStore {
    fn reserve_operation_output(
        &self,
        _thread_id: &str,
        _operation_id: &str,
        max_bytes: u64,
    ) -> Result<u64, pl_core::thread::cold::ColdStoreError> {
        Ok(self.limit.min(max_bytes))
    }

    fn charge_operation_output(
        &self,
        _: &str,
        _: &str,
        total: u64,
    ) -> Result<(), pl_core::thread::cold::ColdStoreError> {
        self.charges.lock().unwrap().push(total);
        Ok(())
    }

    fn admit(
        &self,
        _thread_id: &str,
        _write: pl_core::thread::cold::ThreadWrite,
    ) -> Result<(), pl_core::thread::cold::ColdStoreError> {
        Ok(())
    }

    async fn flush(
        &self,
        _thread_id: &str,
        _sequence: u64,
    ) -> Result<(), pl_core::thread::cold::ColdStoreError> {
        Ok(())
    }
}

fn quota_text_prefix(body: &str) -> Vec<Value> {
    vec![
        json!({"type":"response.created","response":{"id":"partial","model":"reported-fixture"}}),
        json!({"type":"response.output_text.delta","output_index":0,"item_id":"same-item","content_index":0,"delta":body}),
    ]
}

fn quota_retry_prefix() -> Vec<Value> {
    let mut events = quota_text_prefix("accepted retry body");
    events.push(json!({"type":"response.output_item.added","output_index":1,
        "item":{"id":"tool-item","type":"function_call","name":"lookup","call_id":"discarded-call"}}));
    events
}

fn quota_arguments(body: &str) -> Value {
    json!({"type":"response.function_call_arguments.delta","item_id":"tool-item",
        "call_id":"discarded-call","delta":body})
}

fn quota_terminal_failure() -> Value {
    json!({"type":"response.failed","response":{"id":"partial",
        "error":{"code":"invalid_request_error","message":"quota control terminal"}}})
}

struct QuotaRun {
    fixture: FixtureServer,
    thread: ThreadHandle,
    charges: Arc<Mutex<Vec<u64>>>,
    progress: Arc<Mutex<Option<ModelProgressSender>>>,
}

/// Exposes the original producer's counters without implementing any of its accounting.
struct MeteredSession {
    inner: DynModelSession,
    progress: Arc<Mutex<Option<ModelProgressSender>>>,
}

impl CoreModelSession for MeteredSession {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        *self.progress.lock().unwrap() = request.progress.clone();
        self.inner.prepare(request).await
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        self.inner.close().await
    }
}

async fn quota_thread(steps: Vec<Step>, limit: u64) -> QuotaRun {
    let fixture = FixtureServer::start(steps).await.unwrap();
    let runtime = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::compatible("fixture", fixture.base_url()),
        model("live-fixture", ModelTransportProfile::responses_http()),
    )
    .unwrap();
    let session = ModelFactory::new(pl_model::runtime::ThreadModel::new(runtime, None))
        .open_session()
        .await
        .unwrap();
    let progress = Arc::new(Mutex::new(None));
    let thread = ThreadHandle::start(
        "retry-quota-thread".into(),
        DynModelSession::new(MeteredSession {
            inner: session,
            progress: progress.clone(),
        }),
    )
    .unwrap();
    let charges = Arc::new(Mutex::new(Vec::new()));
    thread
        .attach_storage(pl_core::thread::cold::ColdStoreHandle::new(
            OutputQuotaStore {
                limit,
                charges: charges.clone(),
            },
        ))
        .await
        .unwrap();
    QuotaRun {
        fixture,
        thread,
        charges,
        progress,
    }
}

async fn measure_retry_prefix_cost(failed_body: &str) -> (u64, u64, u64) {
    use tokio_util::sync::CancellationToken;
    let first_reached = CancellationToken::new();
    let first_release = CancellationToken::new();
    let retry_reached = CancellationToken::new();
    let retry_release = CancellationToken::new();
    let recovery_reached = CancellationToken::new();
    let recovery_release = CancellationToken::new();
    let QuotaRun {
        fixture,
        thread,
        charges,
        progress,
    } = quota_thread(
        vec![
            Step::prompt(
                Protocol::ResponsesHttp,
                "retry quota",
                0,
                Reply::GatedSse {
                    before: quota_text_prefix(failed_body),
                    reached: first_reached.clone(),
                    release: first_release.clone(),
                    after: vec![],
                },
            ),
            Step::prompt(
                Protocol::ResponsesHttp,
                "retry quota",
                1,
                Reply::SegmentedSse {
                    segments: vec![
                        vec![quota_retry_prefix().remove(0)],
                        quota_retry_prefix().into_iter().skip(1).collect(),
                        vec![],
                    ],
                    gates: vec![
                        (recovery_reached.clone(), recovery_release.clone()),
                        (retry_reached.clone(), retry_release),
                    ],
                },
            ),
        ],
        u64::MAX,
    )
    .await;
    // The store still grants at most the original operation ceiling; this probe measures charges
    // through the real port rather than reproducing envelope sizes or raising production limits.
    let input = user_turn("retry quota");
    let cancellation = input.cancellation.clone();
    let task = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(input).await })
    };
    let mut costs = Vec::new();
    let mut before_retry_body = 0;
    let mut recovery_cost = 0;
    for (generation, reached, body) in [
        (0, &first_reached, failed_body),
        (1, &retry_reached, "accepted retry body"),
    ] {
        tokio::time::timeout(Duration::from_secs(10), reached.cancelled())
            .await
            .unwrap();
        let mut subscription = thread.subscribe();
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                let snapshot = thread.snapshot();
                let starts = thread.effects().await.unwrap();
                if snapshot.model_progress.as_ref().is_some_and(|p| {
                    p.progress.observation().generation == generation
                        && p.progress
                            .observed_part("same-item", PresentationPart::OutputText(0))
                            .is_some_and(|part| part.text() == body)
                }) && starts
                    .iter()
                    .flat_map(|e| e.model_member_starts.iter())
                    .any(|s| s.generation == generation)
                {
                    break;
                }
                subscription.next().await.unwrap();
            }
        })
        .await
        .unwrap();
        costs.push(*charges.lock().unwrap().last().unwrap());
        if generation == 0 {
            first_release.cancel();
            tokio::time::timeout(Duration::from_secs(10), recovery_reached.cancelled())
                .await
                .unwrap();
            before_retry_body = progress.lock().unwrap().as_ref().unwrap().charged_output();
            recovery_cost = *charges.lock().unwrap().last().unwrap();
            recovery_release.cancel();
        } else {
            assert_eq!(
                progress.lock().unwrap().as_ref().unwrap().charged_output(),
                before_retry_body + body.len() as u64,
                "the new generation must charge its body above the original cumulative base"
            );
        }
    }
    cancellation.cancel();
    assert!(
        tokio::time::timeout(Duration::from_secs(5), task)
            .await
            .unwrap()
            .unwrap()
            .is_err()
    );
    thread.close().await.unwrap();
    fixture.shutdown().await.unwrap();
    (costs[0], costs[1], recovery_cost)
}

#[tokio::test]
async fn retry_metadata_failed_body_and_new_tool_arguments_share_the_reliable_quota() {
    let failed_body = "f".repeat(400);
    let rejected_arguments = "x".repeat(400);
    let (first_cost, retry_cost, recovery_cost) = measure_retry_prefix_cost(&failed_body).await;
    // The first case stops exactly after admitted content: the next recovery metadata must not fit.
    // The second admits the whole retried prefix, but not its last argument byte. These costs come
    // from actual Thread output charges, including both starts and their reliable effect envelopes.
    let retry_limit = retry_cost + rejected_arguments.len() as u64 - 1;
    assert!(first_cost < retry_cost);
    assert!(first_cost < recovery_cost && recovery_cost <= retry_cost);
    for (retry, limit) in [(false, first_cost), (true, retry_limit)] {
        let mut steps = vec![Step::prompt(
            Protocol::ResponsesHttp,
            "retry quota",
            0,
            Reply::Sse(quota_text_prefix(&failed_body)),
        )];
        if retry {
            let mut events = quota_retry_prefix();
            events.push(quota_arguments(&rejected_arguments));
            events.push(quota_terminal_failure());
            steps.push(Step::prompt(
                Protocol::ResponsesHttp,
                "retry quota",
                1,
                Reply::Sse(events),
            ));
        }
        let QuotaRun {
            fixture,
            thread,
            charges,
            ..
        } = quota_thread(steps, limit).await;
        assert!(
            tokio::time::timeout(
                Duration::from_secs(10),
                thread.run_turn(user_turn("retry quota"))
            )
            .await
            .unwrap()
            .is_err()
        );
        let snapshot = thread.snapshot();
        assert!(
            snapshot.persistence.resume_required,
            "only the cumulative quota may stop this call"
        );
        assert_eq!(
            snapshot.persistence.fault,
            Some(pl_core::thread::cold::StorageFaultKind::QueueFull)
        );
        let effects = thread.effects().await.unwrap();
        let error = effects
            .iter()
            .find_map(
                |effect| match effect.attempt.as_ref().map(|attempt| &attempt.outcome) {
                    Some(pl_core::thread::AttemptOutcome::Failed(error)) => Some(error),
                    _ => None,
                },
            )
            .unwrap();
        let receipt = pl_model::runtime::model_failure_receipt(error)
            .unwrap()
            .unwrap();
        assert_eq!(
            receipt
                .model_observation
                .as_ref()
                .unwrap()
                .reported_model
                .as_deref(),
            Some("reported-fixture"),
            "local recovery failure must retain provider identity"
        );
        assert!(
            !serde_json::to_string(&receipt)
                .unwrap()
                .contains(&rejected_arguments),
            "refused argument bytes must not enter the retained receipt"
        );
        let progress = receipt.partial_progress.unwrap();
        if !retry {
            assert_eq!(progress.observation().generation, 0);
            assert_eq!(progress.parts()[0].text(), failed_body);
            assert_eq!(charges.lock().unwrap().last().copied(), Some(first_cost));
        } else {
            assert_eq!(progress.observation().generation, 1);
            assert_eq!(
                progress.observation().failed[0].parts[0].text(),
                failed_body
            );
            assert_eq!(progress.parts()[0].text(), "accepted retry body");
            assert_eq!(charges.lock().unwrap().last().copied(), Some(retry_cost));
        }
        assert!(
            snapshot.tasks.is_empty(),
            "refused arguments must never reach execution"
        );
        assert_eq!(
            fixture.finish().await.unwrap().len(),
            if retry { 2 } else { 1 }
        );
        tokio::time::timeout(Duration::from_secs(5), thread.close())
            .await
            .unwrap()
            .unwrap();
    }
    // The exact same current-generation prefix and arguments fit without retained failed output.
    // This control makes a reset-between-generations bug distinguishable from a one-delta overrun.
    let mut fresh = quota_retry_prefix();
    fresh.push(quota_arguments(&rejected_arguments));
    fresh.push(quota_terminal_failure());
    let QuotaRun {
        fixture,
        thread,
        charges,
        ..
    } = quota_thread(
        vec![Step::prompt(
            Protocol::ResponsesHttp,
            "retry quota",
            0,
            Reply::Sse(fresh),
        )],
        retry_limit,
    )
    .await;
    assert!(thread.run_turn(user_turn("retry quota")).await.is_err());
    assert!(
        !thread.snapshot().persistence.resume_required,
        "the same arguments plus current-generation overhead fit independently"
    );
    let fresh_cost = *charges.lock().unwrap().last().unwrap();
    assert!(fresh_cost <= retry_limit);
    assert!(retry_limit < retry_cost + rejected_arguments.len() as u64);
    eprintln!(
        "measured quota intervals: first={first_cost}, recovery={recovery_cost}, retry_prefix={retry_cost}, fresh_with_arguments={fresh_cost}, retry_limit={retry_limit}, refused_arguments={}",
        rejected_arguments.len()
    );
    let effects = thread.effects().await.unwrap();
    let error = effects
        .iter()
        .find_map(|e| match e.attempt.as_ref().map(|a| &a.outcome) {
            Some(pl_core::thread::AttemptOutcome::Failed(error)) => Some(error),
            _ => None,
        })
        .unwrap();
    assert!(
        error.to_string().contains("quota control terminal"),
        "{error}"
    );
    thread.close().await.unwrap();
    assert_eq!(fixture.finish().await.unwrap().len(), 1);
}

/// A provider stream that outgrows the call's reliable output quota is cancelled with what it had.
///
/// The real adapter charges each observed increment through the Thread's own reservation *before* it
/// becomes resident, so this drives the actual decoder, observation producer and reservation end to
/// end instead of a scripted sender calling `charge_output` directly. The stream has to stop at the
/// first chunk the quota cannot hold, keep the bytes it already received readable through the
/// failure receipt, and latch the typed storage fault that holds further model/tool work.
#[tokio::test]
async fn fixture_stream_past_the_reliable_output_quota_cancels_with_a_partial_receipt() {
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "budget prompt",
        0,
        Reply::Sse(vec![
            json!({"type":"response.created","response":{"id":"live-stream","model":"live-fixture"}}),
            json!({"type":"response.output_item.added","output_index":0,
                "item":{"id":"message-1","type":"message","role":"assistant","phase":"final_answer","content":[]}}),
            json!({"type":"response.output_text.delta","item_id":"message-1",
                "output_index":0,"content_index":0,"delta":"answer"}),
            json!({"type":"response.output_text.delta","item_id":"message-1",
                "output_index":0,"content_index":0,"delta":"again".repeat(4096)}),
        ]),
    )])
    .await
    .expect("fixture starts");
    let runtime = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::compatible("fixture", fixture.base_url()),
        model("live-fixture", ModelTransportProfile::responses_http()),
    )
    .expect("fixture endpoint is valid");
    let session = ModelFactory::new(pl_model::runtime::ThreadModel::new(runtime, None))
        .open_session()
        .await
        .expect("model session opens");
    let thread = ThreadHandle::start("quota-thread".into(), session).expect("thread starts");
    thread
        .attach_storage(pl_core::thread::cold::ColdStoreHandle::new(
            // Include reliable start metadata, then refuse the oversized second text delta.
            OutputQuotaStore {
                limit: 16 * 1024,
                ..Default::default()
            },
        ))
        .await
        .expect("storage attaches");

    let runner = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(user_turn("budget prompt")).await }
    });
    let snapshot = {
        let mut subscription = thread.subscribe();
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                let snapshot = subscription.next().await.expect("thread stays open");
                if snapshot.persistence.resume_required {
                    return snapshot;
                }
            }
        })
        .await
        .expect("a stream past the reliable quota must latch the typed fault")
    };
    assert_eq!(
        snapshot.persistence.fault,
        Some(pl_core::thread::cold::StorageFaultKind::QueueFull),
        "the truncation must travel as a typed storage fault, not error text"
    );
    let _ = tokio::time::timeout(Duration::from_secs(10), runner)
        .await
        .expect("the cancelled call ends the Turn");
    let _ = fixture.shutdown().await;

    let effects = thread
        .effects()
        .await
        .expect("failure effects remain reliable");
    let error = effects
        .iter()
        .filter_map(|effect| effect.attempt.as_ref())
        .find_map(|attempt| match &attempt.outcome {
            pl_core::thread::AttemptOutcome::Failed(error) => Some(error.clone()),
            _ => None,
        })
        .expect("the truncated call failed instead of committing");
    let receipt = pl_model::runtime::model_failure_receipt(error.as_ref())
        .expect("the receipt decodes")
        .expect("the failure carries a receipt");
    assert_eq!(
        receipt
            .partial_progress
            .expect("the receipt keeps what was already received")
            .observed_part("message-1", PresentationPart::OutputText(0))
            .expect("the accepted text keeps its identity")
            .text(),
        "answer",
        "the bytes the quota accepted before the refusal stay readable"
    );
    let _ = tokio::time::timeout(Duration::from_secs(10), thread.close()).await;
}

/// Tool-call arguments over the reliable quota are refused before they are copied in.
///
/// The arguments of a function call are output this call may have to retain just like text, so the
/// same reservation bounds them: the stream stops at the first argument chunk the quota cannot hold,
/// the text already accepted stays readable, and no partial (invalid-JSON) call is ever handed to an
/// executor.
#[tokio::test]
async fn fixture_stream_past_the_reliable_output_quota_on_tool_arguments_is_refused() {
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "tool budget prompt",
        0,
        Reply::Sse(vec![
            json!({"type":"response.created","response":{"id":"live-stream","model":"live-fixture"}}),
            json!({"type":"response.output_item.added","output_index":0,
                "item":{"id":"message-1","type":"message","role":"assistant","phase":"final_answer","content":[]}}),
            json!({"type":"response.output_text.delta","item_id":"message-1",
                "output_index":0,"content_index":0,"delta":"answer"}),
            json!({"type":"response.output_item.added","output_index":1,
                "item":{"id":"item-7","type":"function_call","name":"lookup"}}),
            json!({"type":"response.function_call_arguments.delta","item_id":"item-7",
                "call_id":"call-7","delta":"x".repeat(16 * 1024)}),
        ]),
    )])
    .await
    .expect("fixture starts");
    let runtime = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::compatible("fixture", fixture.base_url()),
        model("live-fixture", ModelTransportProfile::responses_http()),
    )
    .expect("fixture endpoint is valid");
    let session = ModelFactory::new(pl_model::runtime::ThreadModel::new(runtime, None))
        .open_session()
        .await
        .expect("model session opens");
    let thread = ThreadHandle::start("tool-quota-thread".into(), session).expect("thread starts");
    // Start metadata and the text delta fit; the oversized argument payload does not.
    thread
        .attach_storage(pl_core::thread::cold::ColdStoreHandle::new(
            OutputQuotaStore {
                limit: 16 * 1024,
                ..Default::default()
            },
        ))
        .await
        .expect("storage attaches");

    let runner = tokio::spawn({
        let thread = thread.clone();
        async move { thread.run_turn(user_turn("tool budget prompt")).await }
    });
    let snapshot = {
        let mut subscription = thread.subscribe();
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                let snapshot = subscription.next().await.expect("thread stays open");
                if snapshot.persistence.resume_required {
                    return snapshot;
                }
            }
        })
        .await
        .expect("tool arguments past the reliable quota must latch the typed fault")
    };
    assert_eq!(
        snapshot.persistence.fault,
        Some(pl_core::thread::cold::StorageFaultKind::QueueFull),
        "the refusal travels as the same typed storage fault text does"
    );
    let _ = tokio::time::timeout(Duration::from_secs(10), runner)
        .await
        .expect("the refused call ends the Turn");
    let _ = fixture.shutdown().await;

    let effects = thread
        .effects()
        .await
        .expect("failure effects remain reliable");
    let error = effects
        .iter()
        .filter_map(|effect| effect.attempt.as_ref())
        .find_map(|attempt| match &attempt.outcome {
            pl_core::thread::AttemptOutcome::Failed(error) => Some(error.clone()),
            _ => None,
        })
        .expect("the refused call failed instead of committing a tool call");
    let receipt = pl_model::runtime::model_failure_receipt(error.as_ref())
        .expect("the receipt decodes")
        .expect("the failure carries a receipt");
    assert_eq!(
        receipt
            .partial_progress
            .expect("the receipt keeps what was already received")
            .observed_part("message-1", PresentationPart::OutputText(0))
            .expect("the accepted text keeps its identity")
            .text(),
        "answer",
        "text accepted before the argument refusal stays readable"
    );
    assert!(
        receipt.presentation_items.is_empty(),
        "no incomplete tool call was materialized from the refused arguments"
    );
    let _ = tokio::time::timeout(Duration::from_secs(10), thread.close()).await;
}

/// A provider tool call whose identity is exposed in stages is charged to the quota once.
///
/// The start announces the item, the argument delta omits the call id, and the closing item finally
/// carries *only* a distinct call id. Keying each event by its own raw identity would charge one call
/// twice — the delta under the item id and the close under the late call id — and refuse a stream
/// that really fits. Resolving identity the way the canonical accumulator does keeps all three
/// events on one key, so the reliable quota sees the call exactly once.
#[derive(Debug)]
struct RecordingLookup {
    calls: Arc<Mutex<Vec<String>>>,
    definition: ToolDefinition,
}

impl Tool for RecordingLookup {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        self.calls.lock().expect("tool log").push(context.call_id);
        Ok(ToolOutput::new(
            input.clone(),
            vec![ContextContent::Text {
                text: Arc::from("lookup result"),
            }],
        ))
    }
}

#[tokio::test]
async fn a_staged_tool_identity_is_charged_once_against_the_reliable_quota() {
    // Fifteen argument bytes: they fit the 25-byte quota once, but two independent charges of the
    // same call would overrun it and falsely refuse a well-formed tool call.
    let arguments = "{\"term\":\"rust\"}";
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "staged identity",
        0,
        Reply::Sse(vec![
            json!({"type":"response.created","response":{"id":"live-stream","model":"live-fixture"}}),
            json!({"type":"response.output_item.added","output_index":0,
                "item":{"id":"item-7","type":"function_call","name":"lookup"}}),
            json!({"type":"response.function_call_arguments.delta","item_id":"item-7",
                "delta":arguments}),
            json!({"type":"response.output_item.done","output_index":0,
                "item":{"call_id":"call-7","type":"function_call","name":"lookup",
                    "arguments":arguments}}),
            // The stream is only terminal once the provider completes the response: without it the
            // accumulator reports an incomplete transport, the runtime retries, and the second
            // request no longer matches this step's *single* scripted reply.
            json!({"type":"response.completed","response":{"id":"live-stream","model":"live-fixture",
                "usage":{"input_tokens":8,"output_tokens":4}}}),
        ]),
    )])
    .await
    .expect("fixture starts");
    let runtime = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::compatible("fixture", fixture.base_url()),
        model("live-fixture", ModelTransportProfile::responses_http()),
    )
    .expect("fixture endpoint is valid");
    let session = ModelFactory::new(pl_model::runtime::ThreadModel::new(runtime, None))
        .open_session()
        .await
        .expect("model session opens");
    let thread = ThreadHandle::start("staged-identity".into(), session).expect("thread starts");
    thread
        .attach_storage(pl_core::thread::cold::ColdStoreHandle::new(
            OutputQuotaStore {
                limit: 25,
                ..Default::default()
            },
        ))
        .await
        .expect("storage attaches");
    let calls = Arc::new(Mutex::new(Vec::new()));
    let definition = ToolDefinition::json(
        "lookup",
        "Look up a term",
        json!({"type": "object", "properties": {"term": {"type": "string"}}}),
    )
    .unwrap();
    let declaration = thread_tool_declaration(&pl_model::completion::tool_definition_to_spec(
        &definition,
        pl_model::completion::ToolCallPolicy::DirectOnly,
    ))
    .expect("a valid function declaration");
    thread
        .register_tools(vec![
            Registration::prepare(
                "lookup".into(),
                // A real tool declaration, encoded exactly as the runtime does, so the request is
                // projected as a normal function tool and the stream reaches the identity resolver.
                declaration,
            )
            .expect("valid tool identity")
            .attach(ToolHandle::new(RecordingLookup {
                calls: calls.clone(),
                definition,
            })),
        ])
        .await
        .expect("tool registers");

    let completed = tokio::time::timeout(
        Duration::from_secs(10),
        thread.run_turn(user_turn("staged identity")),
    )
    .await
    .expect("the staged identity stream must not stall")
    .expect("the stream fits the quota once and completes");
    assert_eq!(completed.model_steps, 1, "one model step produced the call");
    let snapshot = thread.snapshot();
    assert_eq!(
        snapshot.persistence.fault, None,
        "one call exposed in stages must not be charged twice"
    );
    assert!(!snapshot.persistence.resume_required);
    assert_eq!(
        calls.lock().expect("tool log").as_slice(),
        ["call-7"],
        "the resolved call is materialized and dispatched exactly once"
    );
    let _ = fixture.shutdown().await;
    let _ = tokio::time::timeout(Duration::from_secs(10), thread.close()).await;
}

/// A host call without a Thread progress channel still has the same bounded output ceiling.
///
/// The invocation owns a detached observation so failed generations can survive in its receipt.
/// It shares the collector's 16 MiB ceiling across generations: an over-limit delta is refused
/// before becoming accepted content, even when no host installed a progress consumer or cold store.
#[tokio::test]
async fn a_stream_without_a_thread_progress_channel_is_still_bounded() {
    let oversized = "x".repeat(16 * 1024 * 1024 + 1);
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "unbounded",
        0,
        Reply::Sse(vec![
            json!({"type":"response.created","response":{"id":"live-stream","model":"live-fixture"}}),
            json!({"type":"response.output_item.added","output_index":0,
                "item":{"id":"message-1","type":"message","role":"assistant",
                    "phase":"final_answer","content":[]}}),
            json!({"type":"response.output_text.delta","item_id":"message-1",
                "output_index":0,"content_index":0,"delta":oversized}),
        ]),
    )])
    .await
    .expect("fixture starts");
    let runtime = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::compatible("fixture", fixture.base_url()),
        model("live-fixture", ModelTransportProfile::responses_http()),
    )
    .expect("fixture endpoint is valid");

    // No host progress sender or Thread-owned storage reservation.
    let failure = tokio::time::timeout(
        Duration::from_secs(30),
        runtime.complete(
            CompletionRequest::builder()
                .messages(vec![user_message("unbounded")])
                .build(),
            ModelInvocationContext::new(ModelSession::default()),
        ),
    )
    .await
    .expect("the output bound must not stall on an over-limit stream")
    .expect_err("an over-limit stream is refused before retention");
    assert!(
        matches!(&*failure.source, PureError::MemoryError(message) if message.contains("16777216") && message.contains("16777217") && message.contains("retained 0 bytes")),
        "the exact 16 MiB invocation ceiling refuses the first over-limit delta: {:?}",
        failure.source
    );
    let _ = fixture.shutdown().await;
}

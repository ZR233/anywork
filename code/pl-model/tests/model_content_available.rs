//! Reliable first-content facts through the real SSE decoder, collector and Core owner.
use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
    time::Duration,
};

use pl_core::{
    context::ContextContent,
    model::{ModelFactory, ObservedPartIdentity},
    thread::{
        AttemptOutcome, ModelStepLimit, ThreadEffectBatch, ThreadHandle, TurnInput,
        cold::{ColdStore, ColdStoreError, ColdStoreHandle, ThreadWrite},
    },
};
use pl_model::{
    model::{ModelInfo, ModelTransportProfile},
    protocol::ProtocolEndpoint,
    runtime::{ModelRuntime, ThreadModel, model_failure_receipt, model_member_receipt},
};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, ReplyStage, Step};
use serde_json::{Value, json};

const PROMPT: &str = "first public content";

fn input() -> TurnInput {
    TurnInput {
        turn_id: "content-turn".into(),
        attempt_prefix: "content-attempt".into(),
        content: vec![ContextContent::Text {
            text: Arc::from(PROMPT),
        }],
        max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()),
        cancellation: Default::default(),
    }
}

async fn thread(fixture: &FixtureServer) -> ThreadHandle {
    let mut model = ModelInfo::compatible("content-fixture");
    model
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    let runtime = ModelRuntime::new_with_account_id(
        "fixture",
        ProtocolEndpoint::compatible("fixture", fixture.base_url()),
        model,
    )
    .unwrap();
    let session = ModelFactory::new(ThreadModel::new(runtime, None))
        .open_session()
        .await
        .unwrap();
    ThreadHandle::start("first-content".into(), session).unwrap()
}

fn created() -> Value {
    json!({"type":"response.created","response":{"id":"content-response","model":"content-fixture"}})
}

fn opened(id: &str, output_index: u32) -> Value {
    json!({"type":"response.content_part.added","item_id":id,"output_index":output_index,"content_index":0,
        "part":{"type":"output_text","text":""}})
}

fn delta(id: &str, text: &str) -> Value {
    json!({"type":"response.output_text.delta","item_id":id,"content_index":0,"delta":text})
}

fn item(id: &str, text: &str) -> Value {
    json!({"id":id,"type":"message","role":"assistant","status":"completed",
        "content":[{"type":"output_text","text":text}]})
}

fn completed(items: Vec<Value>) -> Value {
    json!({"type":"response.completed","response":{
        "id":"content-response","model":"content-fixture","output":items}})
}

async fn until_effects(
    thread: &ThreadHandle,
    predicate: impl Fn(&[Arc<ThreadEffectBatch>]) -> bool,
) -> Vec<Arc<ThreadEffectBatch>> {
    let mut subscription = thread.subscribe();
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let effects = thread.effects().await.unwrap();
            if predicate(&effects) {
                break effects;
            }
            assert!(
                effects
                    .iter()
                    .filter_map(|e| e.attempt.as_ref())
                    .all(|attempt| { matches!(attempt.outcome, AttemptOutcome::Running) }),
                "the attempt ended before the expected reliable fact: {effects:?}",
            );
            subscription.next().await.unwrap();
        }
    })
    .await
    .expect("the reliable owner must reach the requested fact")
}

#[tokio::test]
async fn content_available_covers_empty_whitespace_delta_closed_and_complete_presentation() {
    // A terminal response can contain multiple normalized events in a single network event.
    // Reasoning without a summary takes the direct PresentationItem path without a Text close.
    for (deltas, final_text, reasoning, response_only) in [
        (vec!["", ""], "", false, false),
        (vec!["", "", "a", "b"], "ab", false, false),
        (vec![], "from authoritative close", false, false),
        (vec![], "whole response", false, true),
        (vec![], "complete reasoning part", true, true),
        (vec![" \n"], " \n", false, false),
        (vec!["**unclosed"], "**unclosed", false, false),
        (vec!["visible prefix"], "", false, false),
    ] {
        let expected_content = !final_text.is_empty() || deltas.iter().any(|s| !s.is_empty());
        let terminal = if reasoning {
            json!({"id":"part","type":"reasoning","status":"completed","summary":[],
                "content":[{"type":"reasoning_text","text":final_text}]})
        } else {
            item("part", final_text)
        };
        let mut events = vec![created()];
        if !deltas.is_empty() {
            events.push(opened("part", 0));
        }
        events.extend(deltas.into_iter().map(|text| delta("part", text)));
        if !response_only {
            events
                .push(json!({"type":"response.output_item.done","output_index":0,"item":terminal}));
        }
        events.push(completed(vec![terminal]));
        let fixture = FixtureServer::start(vec![Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT,
            0,
            Reply::Sse(events),
        )])
        .await
        .unwrap();
        let thread = thread(&fixture).await;
        let result = tokio::time::timeout(Duration::from_secs(10), thread.run_turn(input()))
            .await
            .unwrap();
        assert!(result.is_ok(), "{result:?}");
        let effects = thread.effects().await.unwrap();
        let starts: Vec<_> = effects
            .iter()
            .filter(|e| !e.model_member_starts.is_empty())
            .collect();
        let available: Vec<_> = effects
            .iter()
            .filter(|e| !e.model_member_content_available.is_empty())
            .collect();
        let ended: Vec<_> = effects
            .iter()
            .filter(|e| !e.model_members.is_empty())
            .collect();
        assert_eq!(starts.len(), 1);
        assert_eq!(
            available.len(),
            usize::from(expected_content),
            "{final_text:?}"
        );
        assert_eq!(ended.len(), 1);
        let receipt = model_member_receipt(&ended[0].model_members[0]).unwrap();
        assert_eq!(
            receipt.item.parts[0].text, final_text,
            "the authoritative value is preserved"
        );
        if expected_content {
            assert_eq!(available[0].model_member_content_available.len(), 1);
            let fact = &available[0].model_member_content_available[0];
            assert_eq!(fact.turn_id, "content-turn");
            assert_eq!(fact.attempt_id, "content-attempt:0");
            assert_eq!(fact.generation, 0);
            assert!(matches!(&fact.identity, ObservedPartIdentity::Provider(p)
                if p.item_id.as_ref() == "part" && p.content_index == 0));
            assert!(starts[0].sequence < available[0].sequence);
            assert!(available[0].sequence < ended[0].sequence);
            assert!(available[0].attempt.is_none() && available[0].context.is_none());
        }
        thread.close().await.unwrap();
        fixture.shutdown().await.unwrap();
    }
}

#[tokio::test]
async fn content_available_precedes_the_next_part_start_and_survives_authoritative_empty() {
    let empty = ReplyStage::new();
    let visible = ReplyStage::new();
    let first = item("first", "");
    let second = item("second", "");
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        PROMPT,
        0,
        ReplyStage::staged(
            vec![
                vec![
                    created(),
                    opened("first", 0),
                    delta("first", ""),
                    delta("first", ""),
                ],
                vec![
                    delta("first", " "),
                    delta("first", "**unclosed"),
                    opened("second", 1),
                ],
                vec![
                    json!({"type":"response.output_item.done","output_index":0,"item":first}),
                    json!({"type":"response.output_item.done","output_index":1,"item":second}),
                    completed(vec![first, second]),
                ],
            ],
            &[&empty, &visible],
        ),
    )])
    .await
    .unwrap();
    let thread = thread(&fixture).await;
    let task = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(input()).await })
    };
    tokio::time::timeout(Duration::from_secs(10), empty.wait_reached())
        .await
        .unwrap();
    let prefix = until_effects(&thread, |effects| {
        effects
            .iter()
            .map(|e| e.model_member_starts.len())
            .sum::<usize>()
            == 1
    })
    .await;
    assert!(
        prefix
            .iter()
            .all(|e| e.model_member_content_available.is_empty())
    );
    empty.release();
    tokio::time::timeout(Duration::from_secs(10), visible.wait_reached())
        .await
        .unwrap();
    let prefix = until_effects(&thread, |effects| {
        effects
            .iter()
            .map(|e| e.model_member_starts.len())
            .sum::<usize>()
            == 2
    })
    .await;
    let available: Vec<_> = prefix
        .iter()
        .filter(|e| !e.model_member_content_available.is_empty())
        .collect();
    assert_eq!(
        available.len(),
        1,
        "later start cannot overtake first-content admission"
    );
    let second_start = prefix
        .iter()
        .find(|e| {
            e.model_member_starts.iter().any(|s| {
        matches!(&s.identity, ObservedPartIdentity::Provider(p) if p.item_id.as_ref() == "second")
    })
        })
        .unwrap();
    assert!(available[0].sequence < second_start.sequence);
    assert!(prefix.iter().all(|e| e.model_members.is_empty()));
    visible.release();
    tokio::time::timeout(Duration::from_secs(10), task)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    let effects = thread.effects().await.unwrap();
    assert_eq!(
        effects
            .iter()
            .map(|e| e.model_member_content_available.len())
            .sum::<usize>(),
        1
    );
    let members: Vec<_> = effects
        .iter()
        .flat_map(|e| e.model_members.iter())
        .collect();
    assert_eq!(
        members.len(),
        2,
        "both real empty terminal originals are kept"
    );
    assert!(members.iter().all(|m| {
        model_member_receipt(m).unwrap().item.parts[0]
            .text
            .is_empty()
    }));
    thread.close().await.unwrap();
    fixture.shutdown().await.unwrap();
}

#[tokio::test]
async fn content_available_preserves_before_and_after_first_byte_failure_and_cancellation() {
    for cancel in [false, true] {
        for body in ["", "accepted prefix"] {
            let stage = ReplyStage::new();
            let failure = json!({"type":"response.failed","response":{"id":"content-response",
                "error":{"code":"invalid_request_error","message":"controlled provider failure"}}});
            let fixture = FixtureServer::start(vec![Step::prompt(
                Protocol::ResponsesHttp,
                PROMPT,
                0,
                ReplyStage::staged(
                    vec![
                        vec![
                            created(),
                            opened("part", 0),
                            delta("part", body),
                            opened("sentinel", 1),
                        ],
                        vec![failure],
                    ],
                    &[&stage],
                ),
            )])
            .await
            .unwrap();
            let thread = thread(&fixture).await;
            let input = input();
            let cancellation = input.cancellation.clone();
            let task = {
                let thread = thread.clone();
                tokio::spawn(async move { thread.run_turn(input).await })
            };
            tokio::time::timeout(Duration::from_secs(10), stage.wait_reached())
                .await
                .unwrap();
            until_effects(&thread, |effects| {
                effects
                    .iter()
                    .map(|e| e.model_member_starts.len())
                    .sum::<usize>()
                    == 2
            })
            .await;
            if cancel {
                cancellation.cancel();
            } else {
                stage.release();
            }
            assert!(
                tokio::time::timeout(Duration::from_secs(10), task)
                    .await
                    .unwrap()
                    .unwrap()
                    .is_err()
            );
            let effects = thread.effects().await.unwrap();
            assert_eq!(
                effects
                    .iter()
                    .map(|e| e.model_member_content_available.len())
                    .sum::<usize>(),
                usize::from(!body.is_empty())
            );
            assert!(
                effects.iter().all(|e| e.model_members.is_empty()),
                "no invented independent terminal"
            );
            let terminal = &effects
                .iter()
                .filter_map(|e| e.attempt.as_ref())
                .next_back()
                .unwrap()
                .outcome;
            let error = match terminal {
                AttemptOutcome::Cancelled { result: Err(error) } if cancel => error,
                AttemptOutcome::Failed(error) if !cancel => error,
                outcome => panic!("real failure/cancel outcome must survive: {outcome:?}"),
            };
            let failure = model_failure_receipt(error).unwrap().unwrap();
            let progress = failure.partial_progress.unwrap();
            assert_eq!(
                progress
                    .observed_part("part", pl_core::chat::PresentationPart::OutputText(0))
                    .map(|part| part.text())
                    .unwrap_or_default(),
                body,
            );
            stage.release();
            thread.close().await.unwrap();
            fixture.shutdown().await.unwrap();
        }
    }
}

#[derive(Debug)]
struct CancelMemberStore {
    cancellation: tokio_util::sync::CancellationToken,
    after_content: AtomicBool,
    cancelled_charges: AtomicUsize,
    writes: Mutex<Vec<ThreadWrite>>,
}

#[derive(Debug)]
struct CancelMemberStorage(Arc<CancelMemberStore>);

impl ColdStore for CancelMemberStorage {
    fn admit(&self, _: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
        if !write.effect.model_member_content_available.is_empty() {
            self.0.after_content.store(true, Ordering::SeqCst);
        }
        self.0.writes.lock().unwrap().push(write);
        Ok(())
    }

    fn charge_operation_output(&self, _: &str, _: &str, _: u64) -> Result<(), ColdStoreError> {
        // The owner already acknowledged first content. Cancel the outer invocation during the
        // completed member's retention charge, synchronously before its send-time cancellation check.
        if self.0.after_content.swap(false, Ordering::SeqCst) {
            self.0.cancelled_charges.fetch_add(1, Ordering::SeqCst);
            self.0.cancellation.cancel();
        }
        Ok(())
    }

    async fn flush(&self, _: &str, _: u64) -> Result<(), ColdStoreError> {
        Ok(())
    }
}

#[tokio::test]
async fn cancellation_during_completed_member_handoff_preserves_full_item_in_original_failure() {
    let fixture = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        PROMPT,
        0,
        Reply::Sse(vec![
            created(),
            completed(vec![json!({
                "id":"part","type":"reasoning","status":"completed",
                "summary":[],
                "content":[{"type":"reasoning_text","text":"complete unsent reasoning"}]
            })]),
        ]),
    )])
    .await
    .unwrap();
    let thread = thread(&fixture).await;
    let input = input();
    let store = Arc::new(CancelMemberStore {
        cancellation: input.cancellation.clone(),
        after_content: AtomicBool::new(false),
        cancelled_charges: AtomicUsize::new(0),
        writes: Mutex::new(Vec::new()),
    });
    thread
        .attach_storage(ColdStoreHandle::new(CancelMemberStorage(store.clone())))
        .await
        .unwrap();
    assert!(
        tokio::time::timeout(Duration::from_secs(10), thread.run_turn(input))
            .await
            .unwrap()
            .is_err()
    );
    assert_eq!(store.cancelled_charges.load(Ordering::SeqCst), 1);
    {
        let writes = store.writes.lock().unwrap();
        assert_eq!(
            writes
                .iter()
                .map(|write| write.effect.model_member_content_available.len())
                .sum::<usize>(),
            1
        );
        assert_eq!(
            writes
                .iter()
                .map(|write| write.effect.model_members.len())
                .sum::<usize>(),
            0,
            "cancellation during the retention charge must prevent sending the completed member"
        );
        let terminal = writes
            .iter()
            .filter_map(|write| write.effect.attempt.as_ref())
            .next_back()
            .unwrap();
        let AttemptOutcome::Cancelled { result: Err(error) } = &terminal.outcome else {
            panic!("pre-send cancellation must preserve its original typed outcome: {terminal:?}");
        };
        assert_eq!(error.kind, pl_core::model::ModelFailureKind::Cancelled);
        let failure = model_failure_receipt(error).unwrap().unwrap();
        assert_eq!(failure.presentation_items.len(), 1);
        assert_eq!(failure.presentation_items[0].provider_item_id, "part");
        assert_eq!(
            failure.presentation_items[0].parts[0].text,
            "complete unsent reasoning"
        );
    }
    thread.close().await.unwrap();
    fixture.shutdown().await.unwrap();
}

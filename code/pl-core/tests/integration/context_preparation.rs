use crate::support;
use crate::tool_support;

use pl_core::{
    context::{ContextContent, ContextSource},
    model::DynModelSession,
    thread::{
        RuntimeFact, ThreadHandle,
        context_preparation::{
            ContextPreparation, ContextPreparationHook, ContextPreparationRequest, ContextPreparer,
        },
        input::InputPurpose,
    },
};
use std::sync::{Arc, Mutex};
use support::{ScriptedModel, text, turn};
use tokio_util::sync::CancellationToken;

#[derive(Debug)]
struct ObserveTurnInput(Arc<Mutex<Vec<Option<pl_core::thread::input::ThreadInput>>>>);

impl ContextPreparationHook for ObserveTurnInput {
    async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
        self.0.lock().unwrap().push(request.turn_input);
        ContextPreparation::Unchanged
    }
}

#[tokio::test]
async fn preparation_exposes_only_the_pending_turn_initiator_not_later_tool_steps() {
    use pl_core::{
        context::OpaquePayload,
        thread::input::{InputDriverOptions, ThreadInput},
    };
    let (model, _) = ScriptedModel::new(&["record"]);
    let thread = ThreadHandle::start("turn-input".into(), DynModelSession::new(model)).unwrap();
    let seen = Arc::new(Mutex::new(Vec::new()));
    let calls = Arc::new(Mutex::new(Vec::new()));
    thread
        .register_tools(vec![tool_support::tool("record", &calls)])
        .await
        .unwrap();
    thread
        .set_context_preparation(Some(ContextPreparer::new(ObserveTurnInput(seen.clone()))))
        .await
        .unwrap();
    let mut expected = Vec::new();
    for id in ["first", "next"] {
        let input = ThreadInput {
            id: id.into(),
            purpose: InputPurpose::Message,
            payload: OpaquePayload::text(format!("opaque {id}")),
            context: vec![text(&format!("user input {id}"))],
        };
        expected.extend([Some(input.clone()), None]);
        let request = turn(id);
        let mut updates = thread.subscribe();
        thread
            .submit_input(
                input,
                Some(InputDriverOptions {
                    max_model_steps: request.max_model_steps,
                }),
            )
            .await
            .unwrap();
        tokio::time::timeout(std::time::Duration::from_secs(5), async {
            while let Some(snapshot) = updates.next().await {
                if snapshot.inputs.is_empty() && snapshot.execution.is_none() {
                    return;
                }
            }
        })
        .await
        .expect("immediate input completed");
    }
    // User-shaped context without admitted input is not a new host input identity.
    thread.run_turn(turn("direct-context")).await.unwrap();
    expected.extend([None, None]);
    assert_eq!(*seen.lock().unwrap(), expected);
    assert_eq!(calls.lock().unwrap().len(), 3);
    thread.close().await.unwrap();
}

struct CapacityModel {
    observed: Arc<Mutex<Vec<pl_core::context::ContextSnapshot>>>,
    dispatched: Arc<std::sync::atomic::AtomicUsize>,
    always_exceeds: bool,
    during_execution: bool,
    grants_recovery: bool,
    fail_after_local_recovery: bool,
}
impl pl_core::model::ModelSession for CapacityModel {
    async fn prepare(
        &mut self,
        request: pl_core::model::ModelRequest,
    ) -> Result<pl_core::model::PreparedModelCall, pl_core::model::ModelError> {
        self.observed.lock().unwrap().push(request.context.clone());
        let input_bytes = serde_json::to_vec(&request.context.records).unwrap().len();
        if let Some(grant) = request
            .members
            .as_ref()
            .and_then(|members| members.context_recovery())
        {
            assert!(
                grant
                    .consume(&request.thread_id, &request.turn_id, input_bytes, 2)
                    .is_none()
            );
            let (_, retry, _) = grant
                .consume(&request.thread_id, &request.turn_id, input_bytes, 1)
                .unwrap();
            assert_eq!(retry, 1);
            assert!(
                grant
                    .consume(&request.thread_id, &request.turn_id, input_bytes, 1)
                    .is_none()
            );
        }
        let exceeds = self.always_exceeds
            || request
                .context
                .records
                .iter()
                .any(|record| record.id == "large-history");
        if exceeds && !self.during_execution {
            return Err(pl_core::model::ModelError {
                context_recovery: None,
                kind: pl_core::model::ModelFailureKind::ContextLimit,
                details: None,
                usage: Default::default(),
                source: None,
            });
        }
        let dispatched = self.dispatched.clone();
        let fail_after_local_recovery = self.fail_after_local_recovery;
        let grants_recovery = self.grants_recovery;
        Ok(pl_core::model::PreparedModelCall::new(async move {
            dispatched.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            if exceeds || fail_after_local_recovery {
                return Err(pl_core::model::ModelError {
                    context_recovery: grants_recovery.then(|| {
                        Box::new(pl_core::model::ModelContextRecovery::new(
                            request.thread_id.clone(),
                            request.turn_id.clone(),
                            request.attempt_id.clone(),
                            1,
                            input_bytes,
                            1,
                            None,
                        ))
                    }),
                    kind: pl_core::model::ModelFailureKind::ContextLimit,
                    details: None,
                    usage: Default::default(),
                    source: None,
                });
            }
            Ok(support::response(&request, vec![]))
        }))
    }
    async fn close(&mut self) -> Result<(), pl_core::model::ModelError> {
        Ok(())
    }
}
#[derive(Debug)]
struct CapacityRecovery(Arc<Mutex<Vec<bool>>>);
impl ContextPreparationHook for CapacityRecovery {
    async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
        self.0.lock().unwrap().push(request.force_compaction);
        if !request.force_compaction {
            return ContextPreparation::Unchanged;
        }
        let mut records = vec![pl_core::context::ContextRecord {
            id: "reduced".into(),
            turn_id: None,
            source: ContextSource::Runtime {
                source_id: "summary".into(),
            },
            content: vec![text("completed history")],
            tool_data: Default::default(),
            tool_calls: vec![],
        }];
        records.extend(
            request
                .committed_context
                .records
                .iter()
                .filter(|record| record.source == ContextSource::User)
                .cloned(),
        );
        ContextPreparation::Prepared {
            excluded_tool_ids: Vec::new(),
            inputs: Default::default(),
            instruction_binding: None,
            rejected_mutations: vec![],
            replacement: Some(pl_core::thread::ReplaceContext {
                expected_revision: request.committed_context.revision,
                reason: pl_core::thread::ContextReplacementReason::Compaction,
                records,
            }),
            facts: request.current_facts.to_vec(),
            mutations: vec![],
        }
    }
}

#[tokio::test]
async fn context_overflow_recovers_once_and_consumes_input_once() {
    for (during_execution, always_exceeds, step_limit, grants_recovery) in [
        (false, false, 3, false),
        (false, true, 3, false),
        (true, false, 3, true),
        (true, true, 3, true),
        (true, false, 1, true),
        (true, false, 3, false),
    ] {
        let observed = Arc::new(Mutex::new(Vec::new()));
        let dispatched = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let preparations = Arc::new(Mutex::new(Vec::new()));
        let thread = ThreadHandle::start(
            format!("capacity-{always_exceeds}"),
            DynModelSession::new(CapacityModel {
                observed: observed.clone(),
                dispatched: dispatched.clone(),
                always_exceeds,
                during_execution,
                grants_recovery,
                fail_after_local_recovery: false,
            }),
        )
        .unwrap();
        thread
            .replace_context(pl_core::thread::ReplaceContext {
                expected_revision: 0,
                reason: pl_core::thread::ContextReplacementReason::Rebuild,
                records: vec![pl_core::context::ContextRecord {
                    id: "large-history".into(),
                    turn_id: None,
                    source: ContextSource::Runtime {
                        source_id: "history".into(),
                    },
                    content: vec![text("oversized committed history")],
                    tool_data: Default::default(),
                    tool_calls: vec![],
                }],
            })
            .await
            .unwrap();
        thread
            .set_context_preparation(Some(ContextPreparer::new(CapacityRecovery(
                preparations.clone(),
            ))))
            .await
            .unwrap();
        let mut input = turn("single-input");
        input.max_model_steps =
            pl_core::thread::ModelStepLimit::Limited(step_limit.try_into().unwrap());
        let result = thread.run_turn(input).await;
        let cannot_recover = during_execution && (step_limit == 1 || !grants_recovery);
        assert_eq!(
            result.is_err(),
            always_exceeds || cannot_recover,
            "during_execution={during_execution}"
        );
        assert!(thread.snapshot().model_execution.is_none());
        assert_eq!(
            *preparations.lock().unwrap(),
            if cannot_recover {
                vec![false]
            } else if during_execution {
                vec![false, true, false]
            } else {
                vec![false, true]
            }
        );
        {
            let requests = observed.lock().unwrap();
            assert_eq!(requests.len(), if cannot_recover { 1 } else { 2 });
            for request in requests.iter() {
                assert_eq!(
                    request
                        .records
                        .iter()
                        .filter(|record| record.source == ContextSource::User)
                        .count(),
                    1
                );
            }
        }
        assert_eq!(
            dispatched.load(std::sync::atomic::Ordering::Relaxed),
            if cannot_recover {
                1
            } else if during_execution {
                2
            } else {
                usize::from(!always_exceeds)
            }
        );
        thread.close().await.unwrap();
    }
}

struct MeasuredThenFailed(usize);
impl pl_core::model::ModelSession for MeasuredThenFailed {
    async fn prepare(
        &mut self,
        request: pl_core::model::ModelRequest,
    ) -> Result<pl_core::model::PreparedModelCall, pl_core::model::ModelError> {
        self.0 += 1;
        let fail = self.0 > 1;
        Ok(pl_core::model::PreparedModelCall::new(async move {
            if fail {
                return Err(pl_core::model::ModelError {
                    context_recovery: None,
                    kind: pl_core::model::ModelFailureKind::Unavailable,
                    details: None,
                    usage: Default::default(),
                    source: None,
                });
            }
            let mut output = support::response(&request, vec![]);
            output.usage.input_tokens = Some(100);
            output.usage.output_tokens = Some(20);
            Ok(output)
        })
        .with_usage_binding(pl_core::model::ModelUsageBinding {
            route_identity: Some("measured-route".into()),
            model: "measured-model".into(),
            context_window: Some(1000),
            max_context_window: Some(1000),
            auto_compact_limit: Some(900),
        }))
    }
    async fn close(&mut self) -> Result<(), pl_core::model::ModelError> {
        Ok(())
    }
}

#[derive(Debug)]
struct ObserveUsage(
    Arc<Mutex<Vec<Option<pl_core::thread::context_preparation::PreviousContextUsage>>>>,
);

#[derive(Debug)]
struct ObserveFilteredUsage(Arc<Mutex<Vec<bool>>>);
impl ContextPreparationHook for ObserveFilteredUsage {
    async fn before_step(&self, mut request: ContextPreparationRequest) -> ContextPreparation {
        if let Some(previous) = &request.previous_usage {
            assert!(!previous.matches_input(&request.model));
            request.model.tools = Default::default();
            request.model.solo_tool_ids = Default::default();
            request.model.tool_call_mode = pl_core::model::ToolCallMode::Parallel;
            assert!(previous.matches_input(&request.model));
            let mut altered = request.model.clone();
            Arc::make_mut(&mut altered.context.records)[0].content = vec![text("changed prefix")];
            assert!(!previous.matches_input(&altered));
            altered = request.model.clone();
            altered.tool_call_mode = pl_core::model::ToolCallMode::Sequential;
            assert!(!previous.matches_input(&altered));
        }
        self.0
            .lock()
            .unwrap()
            .push(request.previous_usage.is_some());
        ContextPreparation::Prepared {
            inputs: Default::default(),
            instruction_binding: None,
            rejected_mutations: vec![],
            replacement: None,
            facts: request.current_facts.to_vec(),
            mutations: vec![],
            excluded_tool_ids: vec!["workflow".into()],
        }
    }
}

#[tokio::test]
async fn filtered_tool_plan_keeps_the_previous_measurement_available_for_final_preview() {
    let thread = ThreadHandle::start(
        "filtered-measurement".into(),
        DynModelSession::new(MeasuredThenFailed(0)),
    )
    .unwrap();
    thread
        .register_tools(vec![tool_support::tool("workflow", &Arc::default())])
        .await
        .unwrap();
    let seen = Arc::new(Mutex::new(Vec::new()));
    thread
        .set_context_preparation(Some(ContextPreparer::new(ObserveFilteredUsage(
            seen.clone(),
        ))))
        .await
        .unwrap();
    thread.run_turn(turn("first")).await.unwrap();
    assert!(thread.run_turn(turn("next")).await.is_err());
    assert_eq!(*seen.lock().unwrap(), [false, true]);
    thread.close().await.unwrap();
}
impl ContextPreparationHook for ObserveUsage {
    async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
        self.0.lock().unwrap().push(request.previous_usage);
        ContextPreparation::Unchanged
    }
}

#[tokio::test]
async fn unmeasured_failure_preserves_bound_usage_across_checkpoint_and_next_turn() {
    let thread = ThreadHandle::start(
        "measured".into(),
        DynModelSession::new(MeasuredThenFailed(0)),
    )
    .unwrap();
    thread.run_turn(turn("measured-input")).await.unwrap();
    assert!(thread.run_turn(turn("failed-input")).await.is_err());
    let saved = thread
        .capture_current(CancellationToken::new())
        .await
        .unwrap();
    let saved: pl_core::thread::current::ThreadCurrent =
        serde_json::from_str(&serde_json::to_string(&saved).unwrap()).unwrap();
    thread.close().await.unwrap();
    let (model, _) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::restore_current(saved, Some(DynModelSession::new(model))).unwrap();
    let seen = Arc::new(Mutex::new(Vec::new()));
    thread
        .set_context_preparation(Some(ContextPreparer::new(ObserveUsage(seen.clone()))))
        .await
        .unwrap();
    thread
        .resume_current(
            "next-input".into(),
            pl_core::thread::ModelStepLimit::Limited(4.try_into().unwrap()),
            CancellationToken::new(),
        )
        .await
        .unwrap();
    {
        let observations = seen.lock().unwrap();
        let previous = observations[0]
            .as_ref()
            .expect("last measured prefix survives unmeasured failure");
        assert_eq!(previous.usage.input_tokens, Some(100));
        assert_eq!(previous.usage.output_tokens, Some(20));
        assert_eq!(previous.origin.input_record_count, 1);
        assert_eq!(
            previous.origin.binding.route_identity.as_deref(),
            Some("measured-route")
        );
    }
    thread.close().await.unwrap();
}

#[tokio::test]
async fn independent_sessions_keep_facts_inputs_extensions_and_checkpoints_private() {
    use pl_core::{context::OpaquePayload, thread::extensions::ExtensionMutation};
    let mut sessions = Vec::new();
    for marker in ["root-a", "root-b", "parent", "child-a", "child-b"] {
        let (model, requests) = ScriptedModel::new(&[]);
        let thread = ThreadHandle::start(marker.into(), DynModelSession::new(model)).unwrap();
        thread
            .update_facts(vec![RuntimeFact {
                source_id: "workspace".into(),
                content: vec![text(marker)],
            }])
            .await
            .unwrap();
        thread
            .mutate_extensions(vec![ExtensionMutation::Put {
                id: "state".into(),
                expected_revision: None,
                payload: OpaquePayload::text(marker),
            }])
            .await
            .unwrap();
        let mut input = turn(marker);
        input.content = vec![text(marker)];
        thread.run_turn(input).await.unwrap();
        let saved = thread
            .capture_current(CancellationToken::new())
            .await
            .unwrap();
        thread.close().await.unwrap();
        let restored = ThreadHandle::restore_current(
            saved,
            Some(DynModelSession::new(ScriptedModel::new(&[]).0)),
        )
        .unwrap();
        assert_eq!(
            restored.snapshot().extensions["state"].payload.content(),
            marker
        );
        let encoded = serde_json::to_string(&restored.snapshot().context).unwrap();
        for other in ["root-a", "root-b", "parent", "child-a", "child-b"] {
            assert_eq!(encoded.contains(other), other == marker);
        }
        assert!(
            serde_json::to_string(&requests.lock().unwrap()[0])
                .unwrap()
                .contains(marker)
        );
        sessions.push(restored);
    }
    for session in sessions {
        session.close().await.unwrap();
    }
}

#[tokio::test]
async fn changed_facts_append_without_mutating_observed_history_and_clear_explicitly() {
    let (model, observed) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("facts".into(), DynModelSession::new(model)).unwrap();
    let fact = |value: &str| RuntimeFact {
        source_id: "host.state".into(),
        content: vec![text(value)],
    };
    thread
        .update_facts(vec![fact("approved version one")])
        .await
        .unwrap();
    thread.run_turn(turn("first")).await.unwrap();
    let first = observed.lock().unwrap()[0].records[0].clone();
    thread
        .update_facts(vec![fact("executing version two")])
        .await
        .unwrap();
    let second = thread.snapshot().context;
    assert_eq!(
        second.records[0], first,
        "an already observed prefix must remain unchanged"
    );
    let before = second.clone();
    thread
        .update_facts(vec![fact("executing version two")])
        .await
        .unwrap();
    let unchanged = thread.snapshot().context;
    assert_eq!(unchanged.revision, before.revision);
    assert!(Arc::ptr_eq(&unchanged.records, &before.records));
    thread.update_facts(vec![]).await.unwrap();
    let cleared = thread.snapshot().context;
    assert_eq!(cleared.records[0], first);
    assert!(
        matches!(&cleared.records.last().unwrap().content[0], ContextContent::Text { text } if text.contains("no longer current"))
    );
    thread.close().await.unwrap();
}

#[derive(Debug)]
struct ObservePreview(Arc<Mutex<Vec<pl_core::context::ContextSnapshot>>>);

#[derive(Debug)]
struct RestoreFactAuthority;
impl ContextPreparationHook for RestoreFactAuthority {
    async fn before_step(&self, _request: ContextPreparationRequest) -> ContextPreparation {
        ContextPreparation::Prepared {
            excluded_tool_ids: Vec::new(),
            inputs: Default::default(),
            instruction_binding: None,
            rejected_mutations: vec![],
            replacement: None,
            facts: vec![RuntimeFact {
                source_id: "approved-state".into(),
                content: vec![text("approved")],
            }],
            mutations: vec![],
        }
    }
}

#[tokio::test]
async fn preparation_restores_fact_authority_even_when_the_snapshot_already_exists() {
    let (model, _) = ScriptedModel::new(&[]);
    let thread =
        ThreadHandle::start("restore-fact-authority".into(), DynModelSession::new(model)).unwrap();
    thread
        .replace_context(pl_core::thread::ReplaceContext {
            expected_revision: 0,
            reason: pl_core::thread::ContextReplacementReason::Rebuild,
            records: vec![pl_core::context::ContextRecord {
                id: "restored-state".into(),
                turn_id: None,
                source: ContextSource::RuntimeFact {
                    source_id: "approved-state".into(),
                },
                content: vec![text("approved")],
                tool_data: Default::default(),
                tool_calls: vec![],
            }],
        })
        .await
        .unwrap();
    thread
        .set_context_preparation(Some(ContextPreparer::new(RestoreFactAuthority)))
        .await
        .unwrap();
    thread.run_turn(turn("resume-approved-task")).await.unwrap();
    assert_eq!(thread.snapshot().runtime_facts.len(), 1);
    let state = thread.snapshot();
    thread
        .replace_context(pl_core::thread::ReplaceContext {
            expected_revision: state.context.revision,
            reason: pl_core::thread::ContextReplacementReason::Compaction,
            records: vec![],
        })
        .await
        .unwrap();
    assert_eq!(thread.snapshot().context.records.len(), 1);
    assert_eq!(
        thread.snapshot().context.records[0].content,
        vec![text("approved")]
    );
    thread.close().await.unwrap();
}

impl ContextPreparationHook for ObservePreview {
    async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
        self.0.lock().unwrap().push(request.model.context);
        ContextPreparation::Unchanged
    }
}

#[tokio::test]
async fn preparation_capacity_preview_includes_the_unconsumed_user_input() {
    let (model, observed) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("preview".into(), DynModelSession::new(model)).unwrap();
    let previews = Arc::new(Mutex::new(Vec::new()));
    thread
        .set_context_preparation(Some(ContextPreparer::new(ObservePreview(previews.clone()))))
        .await
        .unwrap();
    thread.run_turn(turn("new-task")).await.unwrap();
    let preview = previews.lock().unwrap()[0].clone();
    assert!(
        preview
            .records
            .iter()
            .any(|r| r.source == ContextSource::User)
    );
    assert_eq!(
        preview,
        observed.lock().unwrap()[0],
        "the capacity preview must match the admitted request"
    );
    thread.close().await.unwrap();
}

#[derive(Debug)]
struct CancelCandidate;
impl ContextPreparationHook for CancelCandidate {
    async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
        use pl_core::{context::OpaquePayload, thread::extensions::ExtensionMutation};
        let put = |id: &str| ExtensionMutation::Put {
            id: id.into(),
            expected_revision: None,
            payload: OpaquePayload::text(id),
        };
        request.model.cancellation.cancel();
        let mut cost = put("observed.cost");
        if let ExtensionMutation::Put {
            expected_revision, ..
        } = &mut cost
        {
            *expected_revision = Some(99);
        }
        ContextPreparation::Prepared {
            excluded_tool_ids: Vec::new(),
            inputs: Default::default(),
            instruction_binding: None,
            rejected_mutations: vec![cost],
            replacement: None,
            facts: vec![RuntimeFact {
                source_id: "state".into(),
                content: vec![text("wrong advance")],
            }],
            mutations: vec![put("success.receipt")],
        }
    }
}

#[tokio::test]
async fn cancelled_candidate_keeps_accounting_without_committing_state_or_success() {
    let (model, observed) = ScriptedModel::new(&[]);
    let thread =
        ThreadHandle::start("cancel-candidate".into(), DynModelSession::new(model)).unwrap();
    thread
        .update_facts(vec![RuntimeFact {
            source_id: "state".into(),
            content: vec![text("approved")],
        }])
        .await
        .unwrap();
    let before = thread.snapshot().context;
    thread
        .set_context_preparation(Some(ContextPreparer::new(CancelCandidate)))
        .await
        .unwrap();
    assert!(thread.run_turn(turn("cancelled")).await.is_err());
    let snapshot = thread.snapshot();
    assert_eq!(snapshot.context, before);
    assert!(snapshot.extensions.contains_key("observed.cost"));
    assert!(!snapshot.extensions.contains_key("success.receipt"));
    assert!(observed.lock().unwrap().is_empty());
    thread.close().await.unwrap();
}

#[derive(Debug)]
struct ChangeReadInput {
    thread: ThreadHandle,
    by_format: bool,
}
impl ContextPreparationHook for ChangeReadInput {
    async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
        use pl_core::{
            context::OpaquePayload,
            thread::extensions::{ExtensionInputs, ExtensionMutation},
        };
        let mut inputs = ExtensionInputs::default();
        if self.by_format {
            inputs.include_format(&request.extensions, "test.skill");
        } else {
            inputs.include_keys(&request.extensions, &["selected"]);
        }
        let value = request.extensions.get("selected");
        let current = value.is_some_and(|entry| entry.payload.content() == "current approved");
        if !current {
            self.thread
                .mutate_extensions(vec![ExtensionMutation::Put {
                    id: "selected".into(),
                    expected_revision: value.map(|entry| entry.revision),
                    payload: OpaquePayload::new("test.skill", 1, "current approved").unwrap(),
                }])
                .await
                .unwrap();
        }
        ContextPreparation::Prepared {
            excluded_tool_ids: Vec::new(),
            inputs,
            instruction_binding: None,
            rejected_mutations: vec![],
            replacement: None,
            facts: vec![RuntimeFact {
                source_id: "state".into(),
                content: vec![text(if current { "current approved" } else { "stale" })],
            }],
            mutations: Vec::new(),
        }
    }
}

#[tokio::test]
async fn a_conflict_refreezes_once_without_admitting_stale_state_or_duplicate_input() {
    use pl_core::{context::OpaquePayload, thread::extensions::ExtensionMutation};
    for (by_format, preexisting) in [(false, true), (false, false), (true, false)] {
        let (model, observed) = ScriptedModel::new(&[]);
        let thread = ThreadHandle::start("conflict".into(), DynModelSession::new(model)).unwrap();
        if preexisting {
            thread
                .mutate_extensions(vec![ExtensionMutation::Put {
                    id: "selected".into(),
                    expected_revision: None,
                    payload: OpaquePayload::text("old"),
                }])
                .await
                .unwrap();
        }
        thread
            .set_context_preparation(Some(ContextPreparer::new(ChangeReadInput {
                thread: thread.clone(),
                by_format,
            })))
            .await
            .unwrap();
        thread.run_turn(turn("retry-preparation")).await.unwrap();
        thread.set_context_preparation(None).await.unwrap();
        {
            let requests = observed.lock().unwrap();
            assert_eq!(requests.len(), 1);
            assert_eq!(
                requests[0]
                    .records
                    .iter()
                    .filter(|record| record.source == ContextSource::User)
                    .count(),
                1
            );
            let encoded = serde_json::to_string(&requests[0]).unwrap();
            assert!(encoded.contains("current approved"));
            assert!(!encoded.contains("stale"));
        }
        thread.close().await.unwrap();
    }
}

#[derive(Debug)]
struct FrozenMailbox {
    first: std::sync::atomic::AtomicBool,
    started: Arc<tokio::sync::Notify>,
    release: Arc<tokio::sync::Notify>,
}
impl ContextPreparationHook for FrozenMailbox {
    async fn before_step(&self, _: ContextPreparationRequest) -> ContextPreparation {
        if self.first.swap(false, std::sync::atomic::Ordering::Relaxed) {
            self.started.notify_one();
            self.release.notified().await;
        }
        ContextPreparation::Unchanged
    }
}

#[tokio::test]
async fn messages_arriving_during_preparation_remain_for_the_next_request() {
    let (model, observed) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::start("watermark".into(), DynModelSession::new(model)).unwrap();
    let started = Arc::new(tokio::sync::Notify::new());
    let release = Arc::new(tokio::sync::Notify::new());
    thread
        .set_context_preparation(Some(ContextPreparer::new(FrozenMailbox {
            first: std::sync::atomic::AtomicBool::new(true),
            started: started.clone(),
            release: release.clone(),
        })))
        .await
        .unwrap();
    let running = thread.clone();
    let task = tokio::spawn(async move { running.run_turn(turn("first")).await });
    started.notified().await;
    let sequence = thread
        .send_message(pl_core::thread::inbox::ThreadMessage {
            kind: pl_core::context::AgentMessageKind::Report,
            id: "late-report".into(),
            source_id: "agent:child".into(),
            payload: pl_core::context::OpaquePayload::text("explicit report"),
            context: vec![text("LATE_CHILD_REPORT")],
        })
        .await
        .unwrap();
    release.notify_one();
    task.await.unwrap().unwrap();
    assert_eq!(thread.snapshot().consumed_messages, 0);
    assert!(
        !serde_json::to_string(&observed.lock().unwrap()[0])
            .unwrap()
            .contains("LATE_CHILD_REPORT")
    );
    thread.run_turn(turn("second")).await.unwrap();
    assert_eq!(thread.snapshot().consumed_messages, sequence);
    {
        let requests = observed.lock().unwrap();
        assert_eq!(
            serde_json::to_string(&requests[1])
                .unwrap()
                .matches("LATE_CHILD_REPORT")
                .count(),
            1
        );
    }
    thread.close().await.unwrap();
}

#[derive(Debug)]
struct HideTool;
impl ContextPreparationHook for HideTool {
    async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
        ContextPreparation::Prepared {
            inputs: Default::default(),
            instruction_binding: None,
            rejected_mutations: vec![],
            replacement: None,
            facts: request.current_facts.to_vec(),
            mutations: vec![],
            excluded_tool_ids: vec!["hidden".into()],
        }
    }
}
struct VisibilityModel {
    seen: Arc<Mutex<Vec<Vec<String>>>>,
    emit_hidden: bool,
}
impl pl_core::model::ModelSession for VisibilityModel {
    async fn prepare(
        &mut self,
        request: pl_core::model::ModelRequest,
    ) -> Result<pl_core::model::PreparedModelCall, pl_core::model::ModelError> {
        self.seen.lock().unwrap().push(
            request
                .tools
                .iter()
                .map(|tool| tool.tool_id.clone())
                .collect(),
        );
        let calls = if self.emit_hidden {
            vec![pl_core::model::ModelToolCall {
                presentation_contract: None,
                rejection: None,
                call_id: "hallucinated".into(),
                tool_id: "hidden".into(),
                arguments: pl_core::context::OpaquePayload::text("must be rejected"),
            }]
        } else {
            vec![]
        };
        Ok(pl_core::model::PreparedModelCall::new(async move {
            Ok(support::response(&request, calls))
        }))
    }
    async fn close(&mut self) -> Result<(), pl_core::model::ModelError> {
        Ok(())
    }
}

#[tokio::test]
async fn prepared_tool_visibility_controls_both_model_declarations_and_call_admission() {
    for emit_hidden in [false, true] {
        let seen = Arc::new(Mutex::new(Vec::new()));
        let calls = Arc::new(Mutex::new(Vec::new()));
        let thread = ThreadHandle::start(
            format!("visibility-{emit_hidden}"),
            DynModelSession::new(VisibilityModel {
                seen: seen.clone(),
                emit_hidden,
            }),
        )
        .unwrap();
        thread
            .register_tools(vec![
                tool_support::tool("hidden", &calls),
                tool_support::tool("visible", &calls),
            ])
            .await
            .unwrap();
        thread
            .set_context_preparation(Some(ContextPreparer::new(HideTool)))
            .await
            .unwrap();
        let result = thread.run_turn(turn("restricted")).await;
        if !emit_hidden {
            result.unwrap();
        }
        assert!(
            !seen.lock().unwrap().is_empty(),
            "the provider must receive the restricted request"
        );
        assert!(
            seen.lock()
                .unwrap()
                .iter()
                .all(|tools| tools == &["visible"])
        );
        assert!(
            calls.lock().unwrap().is_empty(),
            "excluded tools must never execute"
        );
        thread.close().await.unwrap();
    }
}

#[derive(Debug)]
struct RecoveryAsRebuild(Arc<Mutex<Vec<bool>>>);
impl ContextPreparationHook for RecoveryAsRebuild {
    async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
        let mut result = CapacityRecovery(self.0.clone()).before_step(request).await;
        if let ContextPreparation::Prepared {
            replacement: Some(replacement),
            ..
        } = &mut result
        {
            replacement.reason = pl_core::thread::ContextReplacementReason::Rebuild;
        }
        result
    }
}

#[tokio::test]
async fn local_and_service_overflow_share_one_recovery_and_rebuild_is_not_recovery() {
    for (rebuild, shorter) in [(false, true), (false, false), (true, true)] {
        let observed = Arc::new(Mutex::new(Vec::new()));
        let forced = Arc::new(Mutex::new(Vec::new()));
        let thread = ThreadHandle::start(
            format!("mixed-overflow-{rebuild}"),
            DynModelSession::new(CapacityModel {
                observed: observed.clone(),
                dispatched: Default::default(),
                always_exceeds: false,
                during_execution: false,
                grants_recovery: true,
                fail_after_local_recovery: true,
            }),
        )
        .unwrap();
        thread
            .replace_context(pl_core::thread::ReplaceContext {
                expected_revision: 0,
                reason: pl_core::thread::ContextReplacementReason::Rebuild,
                records: vec![pl_core::context::ContextRecord {
                    id: "large-history".into(),
                    turn_id: None,
                    source: ContextSource::Runtime {
                        source_id: "history".into(),
                    },
                    content: vec![text(if shorter {
                        "oversized history that is substantially longer than the replacement summary"
                    } else {
                        "large"
                    })],
                    tool_data: Default::default(),
                    tool_calls: vec![],
                }],
            })
            .await
            .unwrap();
        let hook = if rebuild {
            ContextPreparer::new(RecoveryAsRebuild(forced.clone()))
        } else {
            ContextPreparer::new(CapacityRecovery(forced.clone()))
        };
        thread.set_context_preparation(Some(hook)).await.unwrap();
        let result = thread.run_turn(turn("mixed")).await;
        if !rebuild && shorter {
            assert!(
                matches!(result, Err(pl_core::thread::ThreadError::Model(ref error)) if error.kind == pl_core::model::ModelFailureKind::ContextLimit)
            );
        } else {
            assert!(
                matches!(result, Err(pl_core::thread::ThreadError::ModelRepair { primary, repair })
                if primary.kind == pl_core::model::ModelFailureKind::ContextLimit && matches!(&*repair, pl_core::thread::ThreadError::InvalidContext))
            );
        }
        assert_eq!(*forced.lock().unwrap(), [false, true]);
        assert_eq!(
            observed.lock().unwrap().len(),
            if !rebuild && shorter { 2 } else { 1 }
        );
        thread.close().await.unwrap();
    }
}

#[tokio::test]
async fn forced_compaction_failure_keeps_original_turn_failure_and_never_resends() {
    let dispatched = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let thread = capacity_recovery_thread(dispatched.clone()).await;
    thread
        .set_context_preparation(Some(ContextPreparer::new(FailForcedCompaction)))
        .await
        .unwrap();
    let error = thread.run_turn(turn("repair failure")).await.unwrap_err();
    let pl_core::thread::ThreadError::ModelRepair { primary, repair } = error else {
        panic!("expected paired model and repair failures, got {error}");
    };
    assert_eq!(primary.kind, pl_core::model::ModelFailureKind::ContextLimit);
    assert!(
        matches!(&*repair, pl_core::thread::ThreadError::Model(error) if error.kind == pl_core::model::ModelFailureKind::Unavailable)
    );
    assert!(repair.to_string().contains("controlled compaction failure"));
    assert_eq!(dispatched.load(std::sync::atomic::Ordering::Relaxed), 1);
    thread.close().await.unwrap();
}

#[derive(Debug)]
struct FailForcedCompaction;

impl ContextPreparationHook for FailForcedCompaction {
    async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
        if !request.force_compaction {
            return ContextPreparation::Unchanged;
        }
        ContextPreparation::Failed {
            error: pl_core::model::ModelError {
                context_recovery: None,
                kind: pl_core::model::ModelFailureKind::Unavailable,
                details: None,
                usage: Default::default(),
                source: Some(Box::new(std::io::Error::other(
                    "controlled compaction failure",
                ))),
            },
            mutations: vec![],
        }
    }
}

#[derive(Debug)]
struct StillAboveAutomaticThreshold(Arc<Mutex<Vec<bool>>>);

impl ContextPreparationHook for StillAboveAutomaticThreshold {
    async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
        if request.force_compaction {
            return CapacityRecovery(self.0.clone()).before_step(request).await;
        }
        let is_shorter_but_still_above_threshold = request
            .committed_context
            .records
            .iter()
            .any(|record| record.id == "reduced");
        if is_shorter_but_still_above_threshold && request.enter_compacting().await.is_ok() {
            self.0.lock().unwrap().push(false);
        }
        ContextPreparation::Unchanged
    }
}

#[tokio::test]
async fn post_recovery_preparation_cannot_readmit_compaction() {
    let dispatched = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let thread = capacity_recovery_thread(dispatched.clone()).await;
    let admitted = Arc::new(Mutex::new(Vec::new()));
    thread
        .set_context_preparation(Some(ContextPreparer::new(StillAboveAutomaticThreshold(
            admitted.clone(),
        ))))
        .await
        .unwrap();
    thread.run_turn(turn("one compaction")).await.unwrap();
    assert_eq!(*admitted.lock().unwrap(), [true]);
    assert_eq!(dispatched.load(std::sync::atomic::Ordering::Relaxed), 2);
    thread.close().await.unwrap();
}

async fn capacity_recovery_thread(dispatched: Arc<std::sync::atomic::AtomicUsize>) -> ThreadHandle {
    let thread = ThreadHandle::start(
        "context-repair".into(),
        DynModelSession::new(CapacityModel {
            observed: Default::default(),
            dispatched,
            always_exceeds: false,
            during_execution: true,
            grants_recovery: true,
            fail_after_local_recovery: false,
        }),
    )
    .unwrap();
    thread
        .replace_context(pl_core::thread::ReplaceContext {
            expected_revision: 0,
            reason: pl_core::thread::ContextReplacementReason::Rebuild,
            records: vec![pl_core::context::ContextRecord {
                id: "large-history".into(),
                turn_id: None,
                source: ContextSource::Runtime {
                    source_id: "history".into(),
                },
                content: vec![text(&"large committed history ".repeat(30))],
                tool_data: Default::default(),
                tool_calls: vec![],
            }],
        })
        .await
        .unwrap();
    thread
}

#[tokio::test]
async fn manual_compaction_commits_without_new_input_or_model_turn_and_can_continue() {
    let (model, observed) = ScriptedModel::new(&[]);
    let thread =
        ThreadHandle::start("manual-compaction".into(), DynModelSession::new(model)).unwrap();
    thread.run_turn(turn("original")).await.unwrap();
    let before = thread.snapshot();
    let forced = Arc::new(Mutex::new(Vec::new()));
    thread
        .set_context_preparation(Some(ContextPreparer::new(CapacityRecovery(forced.clone()))))
        .await
        .unwrap();
    let reduced = thread
        .compact_context(before.context.revision, Default::default())
        .await
        .unwrap();
    assert!(reduced.revision > before.context.revision);
    assert_eq!(*forced.lock().unwrap(), [true]);
    assert_eq!(
        observed.lock().unwrap().len(),
        1,
        "the main model must not run a hidden prompt"
    );
    assert_eq!(thread.snapshot().inputs.len(), before.inputs.len());
    assert_eq!(thread.snapshot().turns.len(), before.turns.len());
    assert!(matches!(
        thread
            .compact_context(before.context.revision, Default::default())
            .await,
        Err(pl_core::thread::ThreadError::ContextConflict { .. })
    ));
    let cancelled = tokio_util::sync::CancellationToken::new();
    cancelled.cancel();
    assert!(matches!(
        thread.compact_context(reduced.revision, cancelled).await,
        Err(pl_core::thread::ThreadError::Cancelled)
    ));
    assert_eq!(thread.snapshot().context.revision, reduced.revision);
    thread.run_turn(turn("continue")).await.unwrap();
    assert_eq!(observed.lock().unwrap().len(), 2);
    thread.close().await.unwrap();
}

#[derive(Debug)]
struct ParallelBilling {
    thread: ThreadHandle,
}

impl ContextPreparationHook for ParallelBilling {
    async fn before_step(&self, request: ContextPreparationRequest) -> ContextPreparation {
        use pl_core::{context::OpaquePayload, thread::extensions::ExtensionMutation};
        let id = "studio.auxiliary-billing.title";
        self.thread
            .mutate_extensions(vec![ExtensionMutation::Put {
                id: id.into(),
                expected_revision: request.extensions.get(id).map(|entry| entry.revision),
                payload: OpaquePayload::text("recorded"),
            }])
            .await
            .unwrap();
        ContextPreparation::Prepared {
            inputs: Default::default(),
            instruction_binding: None,
            rejected_mutations: vec![],
            replacement: None,
            facts: request.current_facts.to_vec(),
            mutations: vec![],
            excluded_tool_ids: vec![],
        }
    }
}

#[tokio::test]
async fn unrelated_billing_during_preparation_preserves_the_model_request() {
    let (model, observed) = ScriptedModel::new(&[]);
    let thread =
        ThreadHandle::start("parallel-billing".into(), DynModelSession::new(model)).unwrap();
    thread
        .set_context_preparation(Some(ContextPreparer::new(ParallelBilling {
            thread: thread.clone(),
        })))
        .await
        .unwrap();
    let result = thread.run_turn(turn("prompt")).await;
    thread.set_context_preparation(None).await.unwrap();
    result.unwrap();
    let snapshot = thread.snapshot();
    assert_eq!(
        snapshot.extensions["studio.auxiliary-billing.title"].revision,
        1
    );
    let requests = observed.lock().unwrap().clone();
    assert_eq!(requests.len(), 1);
    assert_eq!(
        requests[0]
            .records
            .iter()
            .filter(|record| record.source == ContextSource::User)
            .count(),
        1
    );
    thread.close().await.unwrap();
}

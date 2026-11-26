//! 用户问答与计划确认的现役投影行为。
//!
//! 这些检查只调用当前 `thread_projection`，不打开冻结的 schema-24 历史库。

use anyhow::{Context, Result};

use super::order;
use crate::{ExecutionItem, ExecutionShape, ItemStamp};

/// 一次普通问答的问题、回答与权威状态。
///
/// 问题原始正文、答案值与私有的 `pl.studio.user-answer` 回执都由这里构造，测试直接用真实
/// 生产者格式验证历史链路，而不是另造一份测试专用协议。
struct QuestionFixture {
    questions: Vec<crate::UserQuestion>,
    answer: serde_json::Value,
}

fn question_fixture() -> QuestionFixture {
    QuestionFixture {
        questions: vec![
            crate::UserQuestion {
                id: "provider".into(),
                header: "Provider".into(),
                question: "Which provider should the next release verify?".into(),
                is_secret: false,
                options: Some(vec![crate::UserQuestionOption {
                    label: "anthropic".into(),
                    description: "Verify the Claude route".into(),
                }]),
            },
            crate::UserQuestion {
                id: "token".into(),
                header: "Token".into(),
                question: "Paste the deployment token".into(),
                is_secret: true,
                options: None,
            },
        ],
        answer: serde_json::json!({
            "answers": {
                "provider": {"answers": ["anthropic\nline two"]},
                "token": {"answers": ["secret-deployment-token"]},
            }
        }),
    }
}

fn interaction_record(
    call_id: &str,
    fixture: &QuestionFixture,
    revision: u64,
    state: pl_core::thread::interactions::InteractionState,
) -> Result<pl_core::thread::interactions::InteractionRecord> {
    Ok(pl_core::thread::interactions::InteractionRecord {
        created_at: 100,
        updated_at: 100 + i64::try_from(revision)?,
        continuation_id: None,
        request: pl_core::thread::interactions::InteractionRequest {
            id: pl_core::tool::opaque::tool_interaction_id(call_id),
            turn_id: "turn-qa".into(),
            payload: pl_core::context::OpaquePayload::new(
                "pl.tool.user-input",
                1,
                serde_json::to_string(&fixture.questions)?,
            )?,
        },
        revision,
        state,
        extension_mutations: vec![],
    })
}

fn answered_record(
    call_id: &str,
    fixture: &QuestionFixture,
) -> Result<pl_core::thread::interactions::InteractionRecord> {
    interaction_record(
        call_id,
        fixture,
        2,
        pl_core::thread::interactions::InteractionState::Resolved(
            pl_core::thread::interactions::InteractionResponse {
                payload: pl_core::context::OpaquePayload::new(
                    "pl.studio.user-answer",
                    1,
                    serde_json::to_string(&fixture.answer)?,
                )?,
                context: vec![],
            },
        ),
    )
}

/// 一条已经提交过、但还没有问答投影的工具条目（旧历史的样子）。
fn question_tool_item(call_id: &str, thread_id: &str, ordinal: u64) -> ExecutionItem {
    ExecutionItem::new(
        order::tool_id(call_id),
        ItemStamp {
            thread_id: thread_id.into(),
            turn_id: "turn-qa".into(),
            ordinal,
            revision: 3,
            created_at: 111,
            updated_at: 222,
        },
        ExecutionShape::Tool(crate::ThreadToolItem::new(
            crate::ThreadToolInvocation::new(
                call_id.into(),
                "request_user_input".into(),
                "{\"questions\":[]}".into(),
            ),
            crate::ThreadToolState::Running(crate::RunningThreadTool::new(String::new())),
        )),
    )
}

fn question_effect(
    commit: i64,
    sequence: u64,
    records: Vec<pl_core::thread::interactions::InteractionRecord>,
) -> pl_core::thread::ThreadEffectBatch {
    pl_core::thread::ThreadEffectBatch {
        committed_at: commit,
        sequence,
        interactions: records.into(),
        ..Default::default()
    }
}

/// 一条真实的计划确认事实：提问正文就是计划文档，hash、问题身份与选项都由生产者格式约束。
fn plan_fixture(plan: &str) -> Result<crate::plan_tool::PlanConfirmationPrompt> {
    use crate::{MessagePresentation, UserQuestion, UserQuestionOption};
    Ok(crate::plan_tool::PlanConfirmationPrompt {
        question: UserQuestion {
            id: crate::AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID.into(),
            header: "Plan".into(),
            question: plan.into(),
            is_secret: false,
            options: Some(vec![
                UserQuestionOption {
                    label: "Approve".into(),
                    description: "Approve this exact Plan and allow the task to proceed.".into(),
                },
                UserQuestionOption {
                    label: "Revise".into(),
                    description: "Request a revised Plan and optionally describe the changes."
                        .into(),
                },
            ]),
        },
        expected_plan_revision: 1,
        document_version: None,
        plan_hash: pl_core::context::content_hash(plan.as_bytes()),
        created_at: 100,
        presentation: MessagePresentation::Hidden,
    })
}

/// `plan_submit` 的工具条目：调用已发起计划确认，旧历史里还没有 typed 计划回执。
fn plan_tool_item(call_id: &str, thread_id: &str, ordinal: u64) -> ExecutionItem {
    ExecutionItem::new(
        order::tool_id(call_id),
        ItemStamp {
            thread_id: thread_id.into(),
            turn_id: "turn-plan".into(),
            ordinal,
            revision: 3,
            created_at: 111,
            updated_at: 222,
        },
        ExecutionShape::Tool(crate::ThreadToolItem::new(
            crate::ThreadToolInvocation::new(
                call_id.into(),
                "plan_submit".into(),
                "{\"expectedRevision\":0,\"plan\":\"# Plan\"}".into(),
            ),
            crate::ThreadToolState::Running(crate::RunningThreadTool::new(String::new())),
        )),
    )
}

fn plan_interaction_record(
    call_id: &str,
    prompt: &crate::plan_tool::PlanConfirmationPrompt,
    revision: u64,
    state: pl_core::thread::interactions::InteractionState,
) -> Result<pl_core::thread::interactions::InteractionRecord> {
    Ok(pl_core::thread::interactions::InteractionRecord {
        created_at: 100,
        updated_at: 100 + i64::try_from(revision)?,
        continuation_id: None,
        request: pl_core::thread::interactions::InteractionRequest {
            id: pl_core::tool::opaque::tool_interaction_id(call_id),
            turn_id: "turn-plan".into(),
            payload: pl_core::context::OpaquePayload::new(
                crate::plan_tool::PLAN_CONFIRMATION_FORMAT,
                1,
                serde_json::to_string(prompt)?,
            )?,
        },
        revision,
        state,
        extension_mutations: vec![],
    })
}

/// 已解决的计划确认：决定标记与用户反馈都留在答案列表里，原样保留。
fn plan_decision_record(
    call_id: &str,
    prompt: &crate::plan_tool::PlanConfirmationPrompt,
    answers: &[&str],
) -> Result<pl_core::thread::interactions::InteractionRecord> {
    plan_interaction_record(
        call_id,
        prompt,
        2,
        pl_core::thread::interactions::InteractionState::Resolved(
            pl_core::thread::interactions::InteractionResponse {
                payload: pl_core::context::OpaquePayload::new(
                    crate::plan_tool::PLAN_ANSWER_FORMAT,
                    1,
                    serde_json::to_string(&serde_json::json!({
                        "answers": {
                            crate::AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID: {
                                "answers": answers
                            }
                        }
                    }))?,
                )?,
                context: vec![],
            },
        ),
    )
}

/// 已回答的问答必须落在原工具条目上：ID、ordinal、创建时间与 Turn 不变，只增加问答正文。
#[test]
fn ordinary_user_answer_updates_the_calling_item_in_place() -> Result<()> {
    let thread = crate::Thread::placeholder("qa-thread");
    let fixture = question_fixture();
    let call_id = "call-qa";
    let saved = question_tool_item(call_id, &thread.id, 7);
    let mut existing = std::collections::BTreeMap::new();
    existing.insert(saved.id.clone(), saved.clone());
    let projection = |record| {
        crate::studio::thread_projection::project_effect_items(
            &thread,
            &pl_core::thread::ThreadSnapshot::default(),
            &question_effect(500, 9, vec![record]),
            &existing,
            &Default::default(),
            &Default::default(),
        )
    };

    let pending = interaction_record(
        call_id,
        &fixture,
        1,
        pl_core::thread::interactions::InteractionState::Pending,
    )?;
    let waiting = projection(pending)?;
    assert_eq!(waiting.items.len(), 1);
    let item = waiting.items[0].tool().context("tool item")?;
    let user_input = item.user_input().context("pending Q&A")?;
    assert!(matches!(
        user_input.state(),
        crate::ThreadToolUserInputState::Pending
    ));
    assert_eq!(user_input.questions().len(), 2);
    assert_eq!(waiting.items[0].id, saved.id);
    assert_eq!(waiting.items[0].ordinal, 7);
    assert_eq!(waiting.items[0].created_at, 111);
    assert_eq!(waiting.items[0].turn_id, "turn-qa");

    let answered = projection(answered_record(call_id, &fixture)?)?;
    // 同一个条目，不是第二条问答记录。
    assert_eq!(answered.items.len(), 1);
    assert_eq!(answered.items[0].id, saved.id);
    assert_eq!(answered.items[0].ordinal, 7);
    assert_eq!(answered.items[0].created_at, 111);
    let user_input = answered.items[0]
        .tool()
        .and_then(|tool| tool.user_input())
        .context("answered Q&A")?;
    let answers = user_input.answers();
    assert_eq!(answers.len(), 2);
    assert_eq!(answers[0].question_id(), "provider");
    assert_eq!(answers[0].answers(), ["anthropic\nline two"]);
    // 敏感回答只公开它已被回答，原值不进入公开投影。
    assert!(answers[1].is_redacted());
    assert!(answers[1].answers().is_empty());
    assert!(answered.items[0].revision >= 1);
    Ok(())
}

/// 计划决定落在发起它的 `plan_submit` 条目上：身份、顺序与创建时间不变，状态与答案都取自
/// 同一份 canonical 交互事实，不因工具成功或当前计划而推演。
#[test]
fn plan_confirmation_history_lands_on_the_submitting_call_in_place() -> Result<()> {
    use crate::ThreadToolUserInputState;

    let thread = crate::Thread::placeholder("plan-thread");
    let plan = "# Plan\n\n1. Migrate the receipts.\n";
    let prompt = plan_fixture(plan)?;
    let saved = plan_tool_item("call-plan", &thread.id, 5);
    let mut existing = std::collections::BTreeMap::new();
    existing.insert(saved.id.clone(), saved.clone());
    let projection = |record| {
        crate::studio::thread_projection::project_effect_items(
            &thread,
            &pl_core::thread::ThreadSnapshot::default(),
            &question_effect(500, 9, vec![record]),
            &existing,
            &Default::default(),
            &Default::default(),
        )
    };

    let waiting = projection(plan_interaction_record(
        "call-plan",
        &prompt,
        1,
        pl_core::thread::interactions::InteractionState::Pending,
    )?)?;
    assert_eq!(waiting.items.len(), 1);
    let item = &waiting.items[0];
    assert_eq!(item.id, saved.id);
    assert_eq!(item.ordinal, 5);
    assert_eq!(item.created_at, 111);
    assert_eq!(item.turn_id, "turn-plan");
    let pending = item
        .tool()
        .and_then(|tool| tool.user_input())
        .context("pending Plan confirmation")?;
    assert_eq!(
        pending.interaction_id(),
        pl_core::tool::opaque::tool_interaction_id("call-plan")
    );
    assert!(matches!(pending.state(), ThreadToolUserInputState::Pending));
    assert_eq!(pending.questions().len(), 1);
    assert_eq!(
        pending.questions()[0].id,
        crate::AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID
    );
    assert_eq!(pending.questions()[0].question, plan);
    assert_eq!(
        pending.questions()[0]
            .options
            .as_ref()
            .map(|options| options.iter().map(|option| option.label.as_str()).collect()),
        Some(vec!["Approve", "Revise"])
    );

    // 请求修改：Revise 标记与完整的用户反馈原样保留在答案列表里，不在历史投影里二次解读。
    let revised = projection(plan_decision_record(
        "call-plan",
        &prompt,
        &["Revise", "split the migration step"],
    )?)?;
    assert_eq!(revised.items.len(), 1);
    let item = &revised.items[0];
    assert_eq!(item.id, saved.id);
    assert_eq!(item.ordinal, 5);
    assert_eq!(item.created_at, 111);
    let decision = item
        .tool()
        .and_then(|tool| tool.user_input())
        .context("resolved Plan confirmation")?;
    let answers = decision.answers();
    assert_eq!(answers.len(), 1);
    assert_eq!(
        answers[0].question_id(),
        crate::AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID
    );
    assert_eq!(answers[0].answers(), ["Revise", "split the migration step"]);
    assert!(!answers[0].is_redacted());
    Ok(())
}

/// 调用正文只剩历史时，投影报告该 identity 让调用方补读，而不是丢下已回答的问答。
#[test]
fn pruned_call_reports_the_identity_instead_of_dropping_the_answer() -> Result<()> {
    let thread = crate::Thread::placeholder("qa-thread");
    let fixture = question_fixture();
    let projection = crate::studio::thread_projection::project_effect_items(
        &thread,
        &pl_core::thread::ThreadSnapshot::default(),
        &question_effect(500, 9, vec![answered_record("call-qa", &fixture)?]),
        &Default::default(),
        &Default::default(),
        &Default::default(),
    )?;
    assert!(projection.items.is_empty());
    assert_eq!(
        projection.unresolved_calls,
        [order::tool_id("call-qa")].into()
    );

    // live 投影只剩放置元数据占位（真实正文已被回收）时同样报告 identity，绝不静默丢弃权威问答。
    let mut placeholder = question_tool_item("call-qa", &thread.id, 7);
    placeholder = placeholder.with_state(ExecutionShape::Raw(crate::ThreadRawItem::stored(
        vec![],
        "This item's body is no longer resident in the live preview cache.",
        111,
    )));
    let mut resident = std::collections::BTreeMap::new();
    resident.insert(placeholder.id.clone(), placeholder.clone());
    let without_body = crate::studio::thread_projection::project_effect_items(
        &thread,
        &pl_core::thread::ThreadSnapshot::default(),
        &question_effect(500, 9, vec![answered_record("call-qa", &fixture)?]),
        &resident,
        &Default::default(),
        &Default::default(),
    )?;
    assert!(without_body.items.is_empty());
    assert_eq!(
        without_body.unresolved_calls,
        [order::tool_id("call-qa")].into()
    );

    // 补读到 durable 正文后，同一次投影就落在原条目上。
    let saved = question_tool_item("call-qa", &thread.id, 7);
    let mut existing = std::collections::BTreeMap::new();
    existing.insert(saved.id.clone(), saved);
    let resolved = crate::studio::thread_projection::project_effect_items(
        &thread,
        &pl_core::thread::ThreadSnapshot::default(),
        &question_effect(500, 9, vec![answered_record("call-qa", &fixture)?]),
        &existing,
        &Default::default(),
        &Default::default(),
    )?;
    resolved.ensure_complete()?;
    assert_eq!(resolved.items.len(), 1);
    assert!(
        resolved.items[0]
            .tool()
            .and_then(|tool| tool.user_input())
            .is_some_and(|input| input.state().is_resolved())
    );
    Ok(())
}

/// 同一调用后续重新投影（任务状态推进、结果交付）不会抹掉已保存的问答。
///
/// 问答属于交互事实，不属于这一次工具状态转移；重新投影必须把它带回同一条目。
#[test]
fn later_projection_of_the_same_call_keeps_the_saved_answer() -> Result<()> {
    use pl_core::thread::task::{TaskRecord, TaskStatus};

    let thread = crate::Thread::placeholder("qa-thread");
    let fixture = question_fixture();
    let mut answered = question_tool_item("call-qa", &thread.id, 7);
    let record = answered_record("call-qa", &fixture)?;
    crate::studio::thread_projection::attach_tool_user_input(
        &mut answered,
        crate::studio::thread_projection::project_tool_user_input(&thread.id, &record)?
            .context("answered Q&A")?,
    )?;
    let mut existing = std::collections::BTreeMap::new();
    existing.insert(answered.id.clone(), answered.clone());
    let task = TaskRecord {
        parent_call_id: None,
        invocation: None,
        id: "task:call-qa".into(),
        call_id: "call-qa".into(),
        tool_id: "request_user_input".into(),
        turn_id: "turn-qa".into(),
        revision: 2,
        status: TaskStatus::Running,
        cancel_requested: false,
        acknowledgement: None,
        started_sequence: Some(9),
    };
    let effect = pl_core::thread::ThreadEffectBatch {
        committed_at: 600,
        sequence: 10,
        tasks: [task].into(),
        ..Default::default()
    };
    let projection = crate::studio::thread_projection::project_effect_items(
        &thread,
        &pl_core::thread::ThreadSnapshot::default(),
        &effect,
        &existing,
        &Default::default(),
        &Default::default(),
    )?;
    let item = projection
        .items
        .iter()
        .find(|item| item.id == answered.id)
        .context("re-projected tool item")?;
    let answers = item
        .tool()
        .and_then(|tool| tool.user_input())
        .context("kept Q&A")?
        .answers();
    assert_eq!(answers[0].answers(), ["anthropic\nline two"]);
    assert!(answers[1].is_redacted());
    Ok(())
}

/// 无法验证的计划事实显式失败：改过的计划正文与内核拒绝的决定都不会被当成批准。
#[test]
fn unverifiable_plan_facts_fail_instead_of_faking_an_approval() -> Result<()> {
    let plan = "# Plan\n\n1. Verified path.\n";
    // 正文与生产者记录的 hash 不再一致。
    let mut tampered = plan_fixture(plan)?;
    tampered.plan_hash = pl_core::context::content_hash(b"another plan");
    let changed = plan_decision_record("call-plan", &tampered, &["Approve"])?;
    let failure =
        crate::studio::thread_projection::project_tool_user_input("plan-thread", &changed)
            .expect_err("a changed Plan text must not be published as approved");
    assert!(failure.to_string().contains("Plan confirmation"));
    assert!(
        !failure.to_string().contains("Verified path"),
        "the diagnostic must not republish the Plan body: {failure}"
    );

    // 决定语义由 Plan 内核判定：同时选择批准与修改、以及没有任何决定的已解决事实都拒绝，
    // 证明历史投影确实复用了 owner 的校验，而不是自己猜一个决定。
    let prompt = plan_fixture(plan)?;
    for answers in [vec!["Approve", "Revise"], vec![]] {
        let rejected = plan_decision_record("call-plan", &prompt, &answers)?;
        let failure =
            crate::studio::thread_projection::project_tool_user_input("plan-thread", &rejected)
                .expect_err("a Plan decision the kernel rejects must not be published");
        let diagnostic = failure.to_string();
        assert!(
            diagnostic.contains("decision is invalid"),
            "the rejection must name the owner decision check: {diagnostic}"
        );
        assert!(
            !diagnostic.contains("Verified path"),
            "the diagnostic must not republish the Plan body: {diagnostic}"
        );
    }
    Ok(())
}

/// 跳过的题不伪造成“已回答但隐藏”：空答案列表只是没有作答，只有真正提供的敏感答案才脱敏。
#[test]
fn skipped_questions_are_not_published_as_hidden_answers() -> Result<()> {
    let fixture = question_fixture();
    let mut record = answered_record("call-skip", &fixture)?;
    record.state = pl_core::thread::interactions::InteractionState::Resolved(
        pl_core::thread::interactions::InteractionResponse {
            payload: pl_core::context::OpaquePayload::new(
                "pl.studio.user-answer",
                1,
                serde_json::to_string(&serde_json::json!({
                    "answers": {
                        "provider": {"answers": ["anthropic"]},
                        "token": {"answers": []},
                    }
                }))?,
            )?,
            context: vec![],
        },
    );

    let projection =
        crate::studio::thread_projection::project_tool_user_input("qa-thread", &record)?
            .context("Q&A")?;
    let answers = projection.answers();
    assert!(projection.state().is_resolved());
    assert_eq!(answers.len(), 1, "an empty answer list is not an answer");
    assert_eq!(answers[0].question_id(), "provider");
    assert_eq!(answers[0].answers(), ["anthropic"]);
    assert!(
        answers.iter().all(|answer| !answer.is_redacted()),
        "a skipped sensitive question must not be published as a hidden answer"
    );

    // 真正提供了值的敏感题仍然只公开“已回答/已隐藏”，原值不进入公开投影。
    let provided = crate::studio::thread_projection::project_tool_user_input(
        "qa-thread",
        &answered_record("call-skip", &fixture)?,
    )?
    .context("provided Q&A")?;
    let secret = provided
        .answers()
        .iter()
        .find(|answer| answer.question_id() == "token")
        .context("sensitive answer")?;
    assert!(secret.is_redacted());
    assert!(secret.answers().is_empty());
    Ok(())
}

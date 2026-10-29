use super::*;
use pl_protocol::{
    AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID, InterruptedThreadTool, ThreadContentLifecycle,
    ThreadPlanDocumentIdentity,
};

fn answered_tool(
    name: &str,
    questions: Vec<UserQuestion>,
    answers: Vec<ThreadToolUserInputAnswer>,
) -> ThreadItem {
    ThreadItem::new(
        "tool:4:call".into(),
        "thread".into(),
        "turn".into(),
        91,
        7,
        10,
        20,
        ThreadItemState::Tool(
            ThreadToolItem::new(
                ThreadToolInvocation::new("call".into(), name.into(), "private arguments".into()),
                ThreadToolState::Interrupted(InterruptedThreadTool::new(20, "finished".into())),
            )
            .with_user_input(Some(ThreadToolUserInput::new(
                "interaction".into(),
                questions,
                ThreadToolUserInputState::Resolved(ResolvedThreadToolUserInput::new(answers)),
            ))),
        ),
    )
}

fn question(id: &str, secret: bool) -> UserQuestion {
    UserQuestion {
        id: id.into(),
        header: "Question".into(),
        question: "# Original document".into(),
        is_other: true,
        is_secret: secret,
        options: None,
    }
}

#[test]
fn completion_fields_never_publish_secret_or_redacted_answers() -> Result<()> {
    let item = answered_tool(
        "ask",
        vec![
            question("secret", true),
            question("hidden", false),
            question("public", false),
        ],
        vec![
            ThreadToolUserInputAnswer::new("secret".into(), vec!["do not publish".into()]),
            ThreadToolUserInputAnswer::redacted("hidden".into()),
            ThreadToolUserInputAnswer::new("public".into(), vec!["visible".into()]),
        ],
    );
    let draft = completion_draft(&item, 4)?;
    assert!(!draft.fields.contains_key(&user_input_answer_field(0, 0)));
    assert!(!draft.fields.contains_key(&user_input_answer_field(1, 0)));
    assert_eq!(
        draft.fields[&user_input_answer_field(2, 0)].text(),
        "visible"
    );
    assert!(
        !draft
            .fields
            .values()
            .any(|body| body.text().contains("do not publish"))
    );
    Ok(())
}

#[test]
fn plan_completion_fields_use_only_the_frozen_document_and_checked_feedback() -> Result<()> {
    let item = answered_tool(
        crate::plan_tool::TOOL_PLAN_SUBMIT,
        vec![question(AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID, false)],
        vec![ThreadToolUserInputAnswer::new(
            AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID.into(),
            vec!["Revise".into(), "  correct this  ".into()],
        )],
    );
    let ThreadItemState::Tool(tool) = item.state() else {
        unreachable!()
    };
    let identity = ThreadPlanDocumentIdentity {
        version: Some(3),
        content_hash: pl_core::context::content_hash(b"# Original document"),
    };
    let input = tool
        .user_input()
        .unwrap()
        .clone()
        .with_plan_document(identity);
    let item = item.clone().with_state(ThreadItemState::Tool(
        ThreadToolItem::new(tool.invocation().clone(), tool.state().clone())
            .with_user_input(Some(input)),
    ));
    let draft = completion_draft(&item, 4)?;
    assert_eq!(draft.fields.len(), 2);
    assert_eq!(
        draft.fields[&ChatField::host(PLAN_DOCUMENT_FIELD)].text(),
        "# Original document"
    );
    assert_eq!(
        draft.fields[&ChatField::host(PLAN_FEEDBACK_FIELD)].text(),
        "correct this"
    );
    assert!(
        !draft
            .fields
            .contains_key(&ChatField::host(TOOL_ARGUMENTS_FIELD))
    );
    let meta = TimelineMeta::decode(&draft.meta)?;
    let pl_protocol::TimelineDescriptor::Plan(plan) = meta.descriptor else {
        anyhow::bail!("Plan completion lost its descriptor");
    };
    assert_eq!(plan.document_version, Some(3));
    assert_eq!(
        plan.decision,
        pl_protocol::TimelinePlanDecision::RevisionRequested
    );
    Ok(())
}

#[test]
fn legacy_completion_parts_are_stable_and_never_claim_original_seal_provenance() -> Result<()> {
    let item = ThreadItem::new(
        "legacy-thinking".into(),
        "thread".into(),
        "turn".into(),
        400,
        800,
        10,
        999,
        ThreadItemState::Thinking(ThreadThinkingItem::new(
            vec!["first".into(), "second".into()],
            vec!["reasoning".into()],
            ThreadContentLifecycle::completed(30),
        )),
    );
    let drafts = legacy_completion_drafts(&item)?;
    let repeated = legacy_completion_drafts(&item)?;
    assert_eq!(drafts.len(), 3);
    let ids: Vec<_> = drafts.iter().map(|draft| draft.item_id.as_str()).collect();
    assert_eq!(
        ids,
        repeated
            .iter()
            .map(|draft| draft.item_id.as_str())
            .collect::<Vec<_>>()
    );
    assert_eq!(
        ids.iter().collect::<std::collections::BTreeSet<_>>().len(),
        3
    );
    let bodies: Vec<_> = drafts
        .iter()
        .map(|draft| draft.fields.values().next().unwrap().text())
        .collect();
    assert_eq!(bodies, ["first", "second", "reasoning"]);
    assert!(
        drafts
            .iter()
            .all(|draft| draft.source_effect_seq.is_none() && draft.sealed_at.is_none())
    );
    let running = item.with_state(ThreadItemState::Thinking(ThreadThinkingItem::new(
        vec!["not completed".into()],
        Vec::new(),
        ThreadContentLifecycle::streaming(),
    )));
    assert!(legacy_completion_drafts(&running)?.is_empty());
    Ok(())
}

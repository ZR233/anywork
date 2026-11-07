use super::*;
use pl_protocol::{ThreadContentLifecycle, ThreadTextChannel};

#[test]
fn active_wait_is_typed_without_payload_and_completion_keeps_only_original_wait() -> Result<()> {
    use pl_protocol::*;
    let waiting = ThreadWaitPresentation::new(
        ThreadWaitIntent::Events {
            targets: vec![ThreadWaitTarget::new(
                "task:timer".into(),
                None,
                None,
                Some(ThreadWaitTargetStatus::Running),
            )],
            timeout_ms: 30_000,
        },
        ThreadWaitState::Waiting,
        None,
    );
    let tool_item = |state, wait| {
        ThreadItem::new(
            "tool:4:call".into(),
            "thread".into(),
            "turn".into(),
            7,
            1,
            10,
            11,
            ThreadItemState::Tool(
                ThreadToolItem::new(
                    ThreadToolInvocation::new("call".into(), "wait".into(), "{}".into()),
                    state,
                )
                .with_wait(wait),
            ),
        )
    };
    let active = tool_item(
        ThreadToolState::Running(RunningThreadTool::new(String::new())),
        Some(waiting.clone()),
    );
    let live = atom(&active);
    assert_eq!(live.id, active.id);
    assert_eq!(live.tool.as_ref().unwrap().call_id, "call");
    assert_eq!(live.wait, Some(waiting.clone()));
    assert!(matches!(live.lifecycle, ChatAtomLifecycle::Active { .. }));
    assert!(live.payload.is_none());
    assert!(live.contents.is_empty());
    assert_eq!(
        serde_json::from_slice::<ChatAtom>(&serde_json::to_vec(&live)?)?,
        live
    );
    // Tool names and generic running state do not manufacture typed Waiting.
    assert!(
        atom(&tool_item(
            ThreadToolState::Running(RunningThreadTool::new(String::new())),
            None,
        ))
        .wait
        .is_none()
    );
    assert!(atom(&text("not-a-tool", String::new())).wait.is_none());

    let handoff = background_started_draft(&active, "task", "accepted", 3, 12, "database")?;
    let handoff_atom: ChatAtom = serde_json::from_slice(&handoff.metadata)?;
    assert!(handoff_atom.wait.is_none());
    assert!(
        serde_json::from_slice::<serde_json::Value>(&handoff.metadata)?
            .get("wait")
            .is_none()
    );

    let ready =
        ThreadWaitPresentation::new(waiting.intent().clone(), ThreadWaitState::Ready, Some(true));
    let terminal = tool_item(
        ThreadToolState::Succeeded(SucceededThreadTool::new(
            12,
            ThreadToolOutput::new("ready".into(), Vec::new(), Vec::new(), None),
        )),
        Some(ready.clone()),
    );
    assert!(atom(&terminal).wait.is_none());
    let draft = completion_draft(&terminal, 4, "database")?;
    let metadata: serde_json::Value = serde_json::from_slice(&draft.metadata)?;
    assert!(metadata.get("wait").is_none());
    let decoded: ChatAtom = serde_json::from_value(metadata)?;
    assert!(
        decoded.wait.is_none(),
        "old metadata without wait must decode"
    );
    let payload: serde_json::Value = serde_json::from_slice(&draft.payload)?;
    assert_eq!(payload["data"]["wait"], serde_json::to_value(ready)?);
    Ok(())
}

#[test]
fn interaction_calls_enter_status_before_user_input_and_keep_identity_through_resolution()
-> Result<()> {
    use crate::studio::thread_projection::timeline::{TimelineInput, TimelineProjection};
    use pl_protocol::*;

    for (name, kind, question_id) in [
        ("request_user_input", ChatAtomKind::Interaction, "question"),
        (
            crate::plan_tool::TOOL_PLAN_SUBMIT,
            ChatAtomKind::Plan,
            AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID,
        ),
    ] {
        let input = |state| {
            ThreadToolUserInput::new(
                "interaction".into(),
                vec![UserQuestion {
                    id: question_id.into(),
                    header: "Confirmation".into(),
                    question: "Continue with this proposal?".into(),
                    is_other: true,
                    is_secret: false,
                    options: None,
                }],
                state,
            )
        };
        let tool_item = |state, user_input| {
            ThreadItem::new(
                "tool:4:call".into(),
                "thread".into(),
                "turn".into(),
                7,
                1,
                10,
                11,
                ThreadItemState::Tool(
                    ThreadToolItem::new(
                        ThreadToolInvocation::new("call".into(), name.into(), "{}".into()),
                        state,
                    )
                    .with_user_input(user_input),
                ),
            )
        };
        for (resolution, terminal_state, outcome) in [
            (
                ThreadToolUserInputState::Resolved(ResolvedThreadToolUserInput::new(vec![
                    ThreadToolUserInputAnswer::new(question_id.into(), vec!["Approve".into()]),
                ])),
                ThreadToolState::Succeeded(SucceededThreadTool::new(
                    12,
                    ThreadToolOutput::new("answered".into(), Vec::new(), Vec::new(), None),
                )),
                ChatTerminalOutcome::Completed,
            ),
            (
                ThreadToolUserInputState::Cancelled,
                ThreadToolState::Interrupted(InterruptedThreadTool::new(12, "cancelled".into())),
                ChatTerminalOutcome::Cancelled,
            ),
        ] {
            let initial = tool_item(
                ThreadToolState::Running(RunningThreadTool::new(String::new())),
                None,
            );
            assert!(initial.tool().unwrap().user_input().is_none());
            assert!(initial.tool().unwrap().wait().is_none());
            let first_atom = atom(&initial);
            assert!(first_atom.payload.is_none());
            assert!(first_atom.contents.is_empty());
            assert!(first_atom.completion_item_id.is_none());
            assert!(first_atom.completion_seq.is_none());

            let pending = tool_item(
                ThreadToolState::Running(RunningThreadTool::new(String::new())),
                Some(input(ThreadToolUserInputState::Pending)),
            );
            let decided = tool_item(
                ThreadToolState::Running(RunningThreadTool::new(String::new())),
                Some(input(resolution.clone())),
            );
            let terminal = tool_item(terminal_state, Some(input(resolution)));
            let mut projection = TimelineProjection::new("database".into(), "generation".into(), 1);
            let mut display_id = None;
            for (item, expected_outcome) in [
                (initial, None),
                (pending, None),
                (decided, None),
                (terminal, Some(outcome)),
            ] {
                let projected_atom = if expected_outcome.is_some() {
                    serde_json::from_slice::<ChatAtom>(
                        &completion_draft(&item, 4, "database")?.metadata,
                    )?
                } else {
                    atom(&item)
                };
                assert_eq!(projected_atom.id, first_atom.id);
                assert_eq!(projected_atom.source, first_atom.source);
                assert_eq!(projected_atom.tool, first_atom.tool);
                assert_eq!(projected_atom.kind, kind);
                assert!(projected_atom.wait.is_none());
                match expected_outcome {
                    None => assert!(matches!(
                        projected_atom.lifecycle,
                        ChatAtomLifecycle::Active {
                            status: ChatActiveStatus::Running,
                            ..
                        }
                    )),
                    Some(expected) => assert!(matches!(
                        projected_atom.lifecycle,
                        ChatAtomLifecycle::Terminal { outcome, .. } if outcome == expected
                    )),
                }
                projection.apply_input(TimelineInput::Atom {
                    atom: Box::new(projected_atom),
                    payload: None,
                })?;
                let mut items = projection.current_items();
                items.extend(projection.take_committed());
                assert_eq!(items.len(), 1, "{name}: interaction must remain one status");
                let status = &items[0];
                assert_eq!(status.kind, TimelineItemKind::Status, "{name}");
                assert_eq!(status.atom_kind, Some(kind));
                assert_eq!(status.source, first_atom.source);
                assert_eq!(status.outcome, expected_outcome);
                assert!(status.members.is_none());
                assert!(status.summary.is_none());
                let first_display_id = display_id.get_or_insert_with(|| status.id.clone());
                assert_eq!(status.id.as_str(), first_display_id.as_str());
            }
        }
    }
    Ok(())
}

fn text(id: &str, body: String) -> ThreadItem {
    ThreadItem::new(
        id.into(),
        "thread".into(),
        "turn:a:b".into(),
        1,
        1,
        10,
        11,
        ThreadItemState::Text(ThreadTextItem::new(
            ThreadTextChannel::Final,
            body,
            Vec::new(),
            ThreadContentLifecycle::completed(11),
        )),
    )
}

#[test]
fn completion_freezes_opaque_payload_and_explicit_large_body_without_embedding_full_text()
-> Result<()> {
    let body = "汉📖".repeat(4000);
    let item = text("text", body.clone());
    let draft = completion_draft(&item, 7, "database")?;
    let envelope: serde_json::Value = serde_json::from_slice(&draft.payload)?;
    assert_eq!(envelope["contract"], "anywork.chat/1");
    assert_eq!(envelope["type"], "text");
    assert_eq!(envelope["sourceEffectSeq"], 7);
    assert_eq!(envelope["sealedAt"], 11);
    assert_eq!(envelope["turnId"], "turn:a:b");
    assert_eq!(envelope["bodies"][0]["byteLength"], body.len() as u64);
    assert!(envelope["bodies"][0].get("inline").is_none());
    assert_eq!(draft.query_class, "conversation");
    let atom: pl_protocol::ChatAtom = serde_json::from_slice(&draft.metadata)?;
    assert_eq!(atom.id, item.id);
    assert_eq!(atom.completion_item_id.as_deref(), Some(item.id.as_str()));
    assert_eq!(atom.completion_seq, None);
    assert_eq!(atom.source_state, None);
    assert!(
        serde_json::from_slice::<serde_json::Value>(&draft.metadata)?
            .get("sourceState")
            .is_none()
    );
    assert_eq!(atom.payload, None);
    assert_eq!(
        atom.source,
        pl_protocol::ChatSourceId::ForegroundTurn {
            turn_id: "turn:a:b".into()
        }
    );
    assert_eq!(atom.contents.len(), 1);
    assert_eq!(draft.parent_id, Some(ChatKey::new("turn", "turn:a:b")?));
    assert!(draft.payload.len() < 2048);
    let reference: ContentRef = serde_json::from_value(envelope["bodies"][0]["reference"].clone())?;
    assert_eq!(
        reference,
        ContentRef {
            database_id: "database".into(),
            target: ContentTarget::Body {
                owner: ContentOwner::Item {
                    item_id: "text".into()
                },
                key: "body".into()
            },
        }
    );
    let key = ChatContentKey {
        owner: crate::studio::conversation_identity::content_owner_key(&ContentOwner::Item {
            item_id: "text".into(),
        })?,
        key: "body".into(),
    };
    let content = &draft.contents[&key];
    assert_eq!(content.descriptor.byte_length, body.len() as u64);
    assert_eq!(
        content.data.range((body.len() - 7) as u64, 7)?.as_bytes(),
        "汉📖".as_bytes()
    );
    assert_eq!(completion_draft(&item, 7, "database")?, draft);
    Ok(())
}

#[test]
fn background_handoff_keeps_member_identity_and_the_distinct_receipt_content_owner() -> Result<()> {
    let item = ThreadItem::new(
        "tool:4:call".into(),
        "thread".into(),
        "turn".into(),
        7,
        1,
        10,
        11,
        ThreadItemState::Tool(ThreadToolItem::new(
            ThreadToolInvocation::new("call".into(), "arbitrary".into(), "{}".into()),
            ThreadToolState::Running(pl_protocol::RunningThreadTool::new(String::new())),
        )),
    );
    let draft = background_started_draft(&item, "task", "accepted", 3, 12, "database")?;
    let atom: pl_protocol::ChatAtom = serde_json::from_slice(&draft.metadata)?;
    assert_eq!(atom.id, item.id);
    assert_ne!(draft.item_id, atom.id);
    assert_eq!(
        atom.completion_item_id.as_deref(),
        Some(draft.item_id.as_str())
    );
    assert_eq!(
        atom.delivery,
        pl_protocol::ChatDeliveryKind::BackgroundHandoff
    );
    assert_eq!(atom.source_state, None);
    assert!(
        serde_json::from_slice::<serde_json::Value>(&draft.metadata)?
            .get("sourceState")
            .is_none()
    );
    assert!(matches!(
        atom.lifecycle,
        pl_protocol::ChatAtomLifecycle::Terminal {
            outcome: pl_protocol::ChatTerminalOutcome::Transferred,
            ..
        }
    ));
    for content in &atom.contents {
        assert!(matches!(&content.reference.target, ContentTarget::Body {
            owner: ContentOwner::Item { item_id }, ..
        } if item_id == &draft.item_id));
    }
    assert_eq!(atom.contents.len(), 2);
    Ok(())
}

#[test]
fn short_body_boundary_is_exact_and_retains_the_manifest() -> Result<()> {
    for len in [0, 4096, 4097] {
        let draft = completion_draft(&text("short", "x".repeat(len)), 3, "database")?;
        let envelope: serde_json::Value = serde_json::from_slice(&draft.payload)?;
        let body = &envelope["bodies"][0];
        assert_eq!(body.get("inline").is_some(), len <= 4096);
        assert_eq!(body.get("reference").is_some(), len > 4096);
        assert_eq!(draft.contents.len(), 1);
        if len <= 4096 {
            assert_eq!(
                serde_json::from_value::<Vec<u8>>(body["inline"].clone())?,
                vec![b'x'; len]
            );
        }
    }
    assert!(completion_draft(&text("missing-db", "body".into()), 1, "").is_err());
    Ok(())
}

#[test]
fn tool_contract_is_frozen_from_the_real_invocation_not_its_name() -> Result<()> {
    for contract in [None, Some("opaque-tool@7")] {
        let invocation = ThreadToolInvocation::new("call".into(), "same-name".into(), "{}".into())
            .with_presentation_contract(contract.map(str::to_owned));
        let item = ThreadItem::new(
            "tool".into(),
            "thread".into(),
            "turn".into(),
            1,
            1,
            10,
            11,
            ThreadItemState::Tool(ThreadToolItem::new(
                invocation,
                ThreadToolState::Succeeded(pl_protocol::SucceededThreadTool::new(
                    11,
                    pl_protocol::ThreadToolOutput::new(
                        "result".into(),
                        Vec::new(),
                        Vec::new(),
                        None,
                    ),
                )),
            )),
        );
        let draft = completion_draft(&item, 3, "database")?;
        assert_eq!(draft.query_class, "conversation");
        let envelope: serde_json::Value = serde_json::from_slice(&draft.payload)?;
        assert_eq!(
            envelope["data"]["invocation"]["presentationContract"],
            serde_json::to_value(contract)?
        );
        assert_eq!(draft.contents.len(), 2);
        let ThreadItemState::Tool(shape) = static_state(item.state()) else {
            panic!("tool shape");
        };
        assert_eq!(shape.invocation().presentation_contract(), contract);
    }
    Ok(())
}

#[test]
fn frozen_text_presence_uses_owned_blocks_not_the_static_shell_or_payload_json() -> Result<()> {
    use anyhow::Context;
    use pl_protocol::{AttachmentModality, ChatAtom, ThreadAttachment};
    for (body, expected) in [("accepted", true), ("", false), (" \n\t", true)] {
        let original = text("presence", body.into());
        let shell = original.clone().with_state(static_state(original.state()));
        assert!(shell.text().context("text")?.text().is_empty());
        assert_eq!(
            atom(&shell).content_present,
            None,
            "a stripped shell claimed emptiness"
        );
        let mut blocks = BTreeMap::from([(BodyKey::Body, ContentBlock::from_text(body))]);
        let draft = freeze(
            &shell,
            CompletionStamp {
                id: &shell.id,
                source_effect_seq: 1,
                sealed_at: 11,
            },
            "database",
            serde_json::to_value(descriptor::item_descriptor(&shell)?)?,
            &mut blocks,
            &ChatContents::new(),
        )?;
        let metadata: ChatAtom = serde_json::from_slice(&draft.metadata)?;
        assert_eq!(metadata.content_present, Some(expected));
    }
    let image = ThreadAttachment {
        id: "image".into(),
        modality: AttachmentModality::Image,
        media_type: "image/png".into(),
        filename: None,
        width: None,
        height: None,
        byte_size: 1,
    };
    let item =
        text("image-only", String::new()).with_state(ThreadItemState::Text(ThreadTextItem::new(
            ThreadTextChannel::Final,
            String::new(),
            vec![image],
            ThreadContentLifecycle::completed(11),
        )));
    let metadata: ChatAtom =
        serde_json::from_slice(&completion_draft(&item, 1, "database")?.metadata)?;
    assert_eq!(metadata.content_present, Some(true));
    Ok(())
}

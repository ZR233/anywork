use super::*;
use pl_protocol::{ThreadContentLifecycle, ThreadTextChannel};

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

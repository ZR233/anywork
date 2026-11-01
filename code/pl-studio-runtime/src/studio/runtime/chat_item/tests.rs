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
        assert_eq!(draft.query_class, "activity");
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

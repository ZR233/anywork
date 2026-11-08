use super::*;
use crate::{ChatAtomKind, ChatDeliveryKind, ChatSourceId, ChatTerminalOutcome, ReadDemand};

fn entry(seq: u64, start: u64, ordinal: u64) -> CompletedEntry {
    CompletedEntry {
        record_id: format!("record:{seq}"),
        completion_seq: seq,
        run: Some(CompletionRunPosition {
            start_seq: start,
            ordinal,
        }),
        main_presentation: MainPresentation::ForegroundWork,
        atom: ChatAtom {
            id: format!("part:{seq}"),
            completion_item_id: Some(format!("record:{seq}")),
            completion_seq: Some(seq),
            source: ChatSourceId::ForegroundTurn {
                turn_id: "turn:one".into(),
            },
            source_state: None,
            source_order: None,
            kind: ChatAtomKind::ToolCall,
            delivery: ChatDeliveryKind::Foreground,
            lifecycle: ChatAtomLifecycle::Terminal {
                started: None,
                ended: None,
                outcome: ChatTerminalOutcome::Completed,
            },
            turn_id: Some("turn:one".into()),
            attempt_id: None,
            tool: None,
            wait: None,
            text_channel: None,
            started_at: None,
            finished_at: None,
            content_present: None,
            contents: Vec::new(),
            payload: Some(PayloadData::Deferred {
                reference: crate::ContentRef {
                    database_id: "database".into(),
                    target: crate::ContentTarget::ItemPayload {
                        item_id: format!("record:{seq}"),
                    },
                },
                byte_length: 100_000,
            }),
        },
    }
}

fn batch(placement: ChatPlacement, entries: Vec<CompletedEntry>) -> ChatBatch {
    ChatBatch {
        placement,
        entries,
        before: None,
        from_seq: (placement == ChatPlacement::Append).then_some(0),
        through_seq: 10,
    }
}

#[test]
fn main_heads_and_live_records_have_distinct_delivery_shapes() {
    let set = batch(ChatPlacement::Set, vec![entry(3, 1, 3), entry(9, 9, 1)]);
    assert!(set.validate_for(&ChatScope::Main).is_ok());
    let records = vec![entry(1, 1, 1), entry(3, 1, 2)];
    assert!(
        batch(ChatPlacement::Set, records.clone())
            .validate_for(&ChatScope::Main)
            .is_err()
    );
    assert!(
        batch(ChatPlacement::Append, records)
            .validate_for(&ChatScope::Main)
            .is_ok()
    );
    let mut hidden = entry(5, 5, 1);
    hidden.main_presentation = MainPresentation::Hidden;
    hidden.run = None;
    let hidden_batch = batch(ChatPlacement::Set, vec![hidden]);
    assert!(hidden_batch.validate_for(&ChatScope::Main).is_err());
    assert!(
        hidden_batch
            .validate_for(&ChatScope::Children {
                parent_id: "4:turnone".into()
            })
            .is_ok()
    );
}

#[test]
fn collapsed_work_rejects_inline_payload_even_for_one_member() {
    let mut one = entry(1, 1, 1);
    one.atom.payload = Some(PayloadData::Inline {
        bytes: "完整结果".as_bytes().to_vec(),
    });
    let value = batch(ChatPlacement::Set, vec![one.clone()]);
    assert!(value.validate_for(&ChatScope::Main).is_err());
    let scope = ChatScope::Run {
        reference: CompletionRunRef {
            database_id: "database".into(),
            index_version: COMPLETED_READ_INDEX_VERSION,
            start_seq: 1,
        },
    };
    assert!(value.validate_for(&scope).is_ok());
    one.main_presentation = MainPresentation::Single;
    assert!(
        batch(ChatPlacement::Set, vec![one])
            .validate_for(&ChatScope::Main)
            .is_ok()
    );
}

#[test]
fn filtered_append_advances_prefix_without_inserting_a_fake_record() {
    let mut value = batch(ChatPlacement::Append, Vec::new());
    value.from_seq = Some(8);
    assert!(value.validate_for(&ChatScope::Main).is_ok());
    value.through_seq = 8;
    assert!(value.validate_for(&ChatScope::Main).is_err());
    value.through_seq = 10;
    value.before = Some("old-page".into());
    assert!(value.validate_for(&ChatScope::Main).is_err());
    value.placement = ChatPlacement::Prepend;
    assert!(value.validate_for(&ChatScope::Main).is_err());
    value.from_seq = None;
    assert!(value.validate_for(&ChatScope::Main).is_ok());
}

#[test]
fn empty_result_does_not_legalize_an_invalid_run_reference() {
    let value = batch(ChatPlacement::Set, Vec::new());
    for (database_id, index_version, start_seq) in [("", 1, 1), ("db", 0, 1), ("db", 1, 0)] {
        assert!(
            value
                .validate_for(&ChatScope::Run {
                    reference: CompletionRunRef {
                        database_id: database_id.into(),
                        index_version,
                        start_seq,
                    },
                })
                .is_err()
        );
    }
}

#[test]
fn completion_identity_order_and_cut_are_checked_before_delivery() {
    let mut value = batch(ChatPlacement::Append, vec![entry(3, 1, 2)]);
    value.from_seq = Some(3);
    assert!(value.validate_for(&ChatScope::Main).is_err());
    value.from_seq = Some(2);
    value.entries[0].atom.completion_seq = Some(4);
    assert!(value.validate_for(&ChatScope::Main).is_err());
    value.entries[0].atom.completion_seq = Some(3);
    value.through_seq = 2;
    assert!(value.validate_for(&ChatScope::Main).is_err());
    value.through_seq = i64::MAX as u64 + 1;
    assert!(value.validate_for(&ChatScope::Main).is_err());
    value.through_seq = 10;
    value.entries[0].run.as_mut().unwrap().ordinal = u64::MAX;
    assert!(value.validate_for(&ChatScope::Main).is_err());
}

#[test]
fn envelope_budget_counts_metadata_and_rejects_old_update_protocol() {
    let value = batch(ChatPlacement::Set, vec![entry(1, 1, 1)]);
    let bytes = serde_json::to_vec(&value).unwrap();
    assert_eq!(value.encoded_len().unwrap(), bytes.len());
    let decoded: ChatBatch = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(value, decoded);
    assert!(
        ReadDemand {
            max_items: 1,
            max_bytes: bytes.len() as u32,
        }
        .validate(bytes.len())
        .is_ok()
    );
    assert!(
        ReadDemand {
            max_items: 1,
            max_bytes: bytes.len() as u32 - 1,
        }
        .validate(bytes.len())
        .is_err()
    );
    assert!(serde_json::from_str::<ChatPlacement>("\"update\"").is_err());
    assert!(
        serde_json::from_str::<ChatBatch>(
            r#"{"placement":"set","entries":[],"before":null,"current":null}"#
        )
        .is_err()
    );
}

#[test]
fn business_refs_are_required_on_state_and_inbox_identity_is_source_scoped() {
    let snapshot = crate::ThreadSnapshot::empty("thread");
    assert_eq!(snapshot.schema_version, 17);
    let mut value = serde_json::to_value(&snapshot).unwrap();
    assert!(value.get("businessRefs").is_some());
    value.as_object_mut().unwrap().remove("businessRefs");
    assert!(serde_json::from_value::<crate::ThreadSnapshot>(value).is_err());

    let source = crate::ChatSourceId::InboxMessage {
        source_id: "platform:account:chat".into(),
        message_id: "received:one".into(),
    };
    let encoded = serde_json::to_value(&source).unwrap();
    assert_eq!(encoded["kind"], "inboxMessage");
    assert_eq!(encoded["sourceId"], "platform:account:chat");
    assert_eq!(
        serde_json::from_value::<crate::ChatSourceId>(encoded).unwrap(),
        source
    );
}

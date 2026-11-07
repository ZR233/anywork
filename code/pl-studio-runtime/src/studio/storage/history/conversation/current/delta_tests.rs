//! Real SQLite tests of the explicit preparation/writer boundary.
use super::*;
use pl_core::chat::ChatDraft;
use sea_orm::TransactionTrait;
use std::{collections::BTreeMap, sync::Mutex};

fn body(owner: ChatKey, generation: u64, text: &[u8]) -> Arc<ChatContent> {
    Arc::new(ChatContent {
        descriptor: ContentDescriptor {
            key: ChatContentKey {
                owner,
                key: "body".into(),
            },
            generation,
            byte_length: text.len() as u64,
            media_type: None,
        },
        data: ContentData::Bytes(Arc::from(text)),
    })
}

fn prepared(sequence: u64) -> PreparedCurrent {
    PreparedCurrent::new(
        FrozenCurrentProjection::new(CurrentProjection::empty(
            sequence,
            pl_protocol::ThreadStatus::Idle,
        )),
        Arc::from([]),
        Arc::from([]),
    )
}

#[tokio::test]
async fn reliable_current_delta_unchanged_sql_is_independent_of_old_owners_and_collections()
-> Result<()> {
    let mut curves = Vec::new();
    for size in [1, 64, 512] {
        let (_dir, mut db) = super::super::tests::fixture().await?;
        let mut seed = prepared(1);
        let mut projection = seed.projection().clone();
        projection.collections.push(CurrentCollectionRef {
            database_id: "database".into(),
            collection: "old-entries".into(),
            revision: 1,
        });
        seed.replace_projection(FrozenCurrentProjection::new(projection));
        seed.contents = (0..size)
            .flat_map(|id| {
                [
                    CurrentContentWrite {
                        content: body(
                            ChatKey::new("item", &format!("unrelated:{id}")).unwrap(),
                            1,
                            b"active",
                        ),
                        sealed: false,
                    },
                    CurrentContentWrite {
                        content: body(
                            crate::studio::conversation_identity::content_owner_key(
                                &pl_protocol::ContentOwner::Current {
                                    domain: "unrelated".into(),
                                    id: id.to_string(),
                                    revision: 1,
                                },
                            )
                            .unwrap(),
                            1,
                            b"owned",
                        ),
                        sealed: true,
                    },
                ]
            })
            .collect();
        seed.changes = (0..size)
            .map(|id| {
                CurrentEntryChange::Put(CurrentEntryWrite {
                    collection: "old-entries".into(),
                    entry_id: id.to_string(),
                    position: id,
                    payload: Arc::from(b"{}".as_slice()),
                })
            })
            .collect();
        apply(&db, 1, &seed).await?;
        let sql = Arc::new(Mutex::new(BTreeMap::<String, usize>::new()));
        let measured = sql.clone();
        db.set_metric_callback(move |info| {
            assert!(!info.failed);
            let mut sql = measured.lock().unwrap();
            assert!(sql.len() < 32);
            *sql.entry(info.statement.sql.clone()).or_default() += 1;
        });
        for sequence in 2..=5 {
            let mut unchanged = prepared(sequence);
            let mut head = seed.projection().clone();
            head.source_effect_seq = sequence;
            unchanged.replace_projection(FrozenCurrentProjection::new(head));
            apply(&db, sequence, &unchanged).await?;
        }
        db.set_metric_callback(|_| {});
        let captured = sql.lock().unwrap().clone();
        assert!(!captured.is_empty());
        for template in captured.keys() {
            assert!(!template.contains("conversation_contents"), "{template}");
            assert!(
                !template.contains("conversation_content_chunks"),
                "{template}"
            );
            assert!(
                !template.contains("conversation_view_entries"),
                "{template}"
            );
        }
        let count: i64 = db
            .query_one_raw(statement(
                "SELECT COUNT(*) AS count FROM conversation_contents",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "count")?;
        assert_eq!(
            count,
            size * 3,
            "unrelated owners must not be enumerated or retired"
        );
        eprintln!(
            "A unchanged writer: old_owners={}, old_collection_rows={size}, effects=4, SQL={captured:?}",
            size * 2
        );
        curves.push(captured);
    }
    assert_eq!(curves[0], curves[1]);
    assert_eq!(curves[1], curves[2]);
    Ok(())
}

#[tokio::test]
async fn reliable_current_delta_exact_retirement_preserves_completion_and_new_generation()
-> Result<()> {
    let (_dir, db) = super::super::tests::fixture().await?;
    let owner = ChatKey::new("item", "handoff")?;
    let initial = body(owner.clone(), 1, b"old");
    let mut first = prepared(1);
    first.contents = Arc::from([CurrentContentWrite {
        content: initial.clone(),
        sealed: false,
    }]);
    apply(&db, 1, &first).await?;
    let replacement = body(owner, 2, b"replacement");
    let mut second = prepared(2);
    second.contents = Arc::from([CurrentContentWrite {
        content: replacement.clone(),
        sealed: false,
    }]);
    apply(&db, 2, &second).await?;
    let tx = db.begin().await?;
    let mut stale_retirement = prepared(3);
    stale_retirement.retirements = Arc::from([CurrentContentRetirement::new(&initial.descriptor)?]);
    assert!(apply(&tx, 3, &stale_retirement).await.is_err());
    tx.rollback().await?;
    assert!(
        super::super::content::validate_content(&db, &replacement)
            .await?
            .is_some()
    );

    let tx = db.begin().await?;
    let mut completion = ChatItem::complete(
        ChatDraft::new("handoff", "conversation", Arc::from(b"{}".as_slice())),
        1,
    );
    completion.contents = Arc::new(pl_core::chat::ChatContents::from([(
        replacement.descriptor.key.clone(),
        replacement.clone(),
    )]));
    super::super::append_records(&tx, [&completion], true).await?;
    let mut third = prepared(3);
    third.retirements = Arc::from([CurrentContentRetirement::new(&replacement.descriptor)?]);
    apply(&tx, 3, &third).await?;
    let manifest = super::super::content::validate_content(&tx, &replacement)
        .await?
        .unwrap();
    assert!(
        manifest.sealed,
        "completion-first handoff must keep the completed body"
    );
    verify(&tx, &third).await?;
    tx.commit().await?;

    let withdrawn = body(ChatKey::new("item", "withdrawn")?, 7, b"withdraw");
    let mut fourth = prepared(4);
    fourth.contents = Arc::from([CurrentContentWrite {
        content: withdrawn.clone(),
        sealed: false,
    }]);
    apply(&db, 4, &fourth).await?;
    let mut fifth = prepared(5);
    fifth.retirements = Arc::from([CurrentContentRetirement::new(&withdrawn.descriptor)?]);
    apply(&db, 5, &fifth).await?;
    assert!(
        super::super::content::validate_content(&db, &withdrawn)
            .await?
            .is_none()
    );
    let chunks: i64 = db
        .query_one_raw(statement(
            "SELECT COUNT(*) AS count FROM conversation_content_chunks WHERE owner_key=?",
            vec![withdrawn.descriptor.key.owner.as_str().into()],
        ))
        .await?
        .unwrap()
        .try_get("", "count")?;
    assert_eq!(chunks, 0);
    Ok(())
}

#[tokio::test]
async fn reliable_current_delta_new_qualification_rejects_unpublished_body_and_item() -> Result<()>
{
    let (_dir, db) = super::super::tests::fixture().await?;
    for target in [
        pl_protocol::ContentTarget::ItemPayload {
            item_id: "not-published".into(),
        },
        pl_protocol::ContentTarget::Body {
            owner: pl_protocol::ContentOwner::Item {
                item_id: "not-published".into(),
            },
            key: "body".into(),
        },
    ] {
        let mut current = prepared(1);
        current.references = Arc::from([pl_protocol::ContentRef {
            database_id: "database".into(),
            target,
        }]);
        let tx = db.begin().await?;
        let error = apply(&tx, 1, &current).await.unwrap_err();
        assert!(error.to_string().contains("unpublished content reference"));
        tx.rollback().await?;
    }
    Ok(())
}

use super::super::current::{self, CurrentContentWrite, PreparedCurrent};
use super::*;
use crate::studio::thread_projection::FrozenCurrentProjection;
use pl_core::chat::{ChatDraft, ChatItem};
use sea_orm::TransactionTrait;

fn body(text: &[u8], generation: u64) -> ChatContent {
    ChatContent {
        descriptor: ContentDescriptor {
            key: ChatContentKey {
                owner: ChatKey::new("item", "incremental").unwrap(),
                key: "body".into(),
            },
            generation,
            byte_length: text.len() as u64,
            media_type: Some("text/plain".into()),
        },
        data: ContentData::Bytes(Arc::from(text)),
    }
}

#[tokio::test]
async fn incremental_content_requires_exact_expected_state_and_legal_transitions() -> Result<()> {
    let (_dir, db) = super::super::tests::fixture().await?;
    let initial = body(b"prefix", 1);
    write_operation(&db, &initial, false, &CurrentContentOperation::Create, None).await?;
    assert!(
        write_operation(&db, &initial, false, &CurrentContentOperation::Create, None)
            .await
            .is_err()
    );
    let appended = body(b"prefix delta", 1);
    let expected = CurrentContentState::new(&initial.descriptor, false);
    let mut wrong = vec![expected.clone(); 4];
    wrong[0].generation += 1;
    wrong[1].byte_length += 1;
    wrong[2].media_type = None;
    wrong[3].sealed = true;
    for wrong in wrong {
        assert!(
            write_operation(
                &db,
                &appended,
                false,
                &CurrentContentOperation::Append(wrong),
                None
            )
            .await
            .is_err()
        );
    }
    assert!(
        write_operation(
            &db,
            &body(b"prefix delta", 2),
            false,
            &CurrentContentOperation::Append(expected.clone()),
            None
        )
        .await
        .is_err()
    );
    assert!(
        write_operation(
            &db,
            &body(b"replacement", 1),
            false,
            &CurrentContentOperation::Replace(expected.clone()),
            None
        )
        .await
        .is_err()
    );
    assert!(
        write_operation(
            &db,
            &appended,
            true,
            &CurrentContentOperation::Seal(expected.clone()),
            None
        )
        .await
        .is_err()
    );
    write_operation(
        &db,
        &appended,
        false,
        &CurrentContentOperation::Append(expected),
        None,
    )
    .await?;
    let replacement = body(b"new generation", 2);
    write_operation(
        &db,
        &replacement,
        false,
        &CurrentContentOperation::Replace(CurrentContentState::new(&appended.descriptor, false)),
        None,
    )
    .await?;
    let expected = CurrentContentState::new(&replacement.descriptor, false);
    write_operation(
        &db,
        &replacement,
        true,
        &CurrentContentOperation::Seal(expected),
        None,
    )
    .await?;
    assert!(
        write_operation(
            &db,
            &body(b"new generation more", 2),
            false,
            &CurrentContentOperation::Append(CurrentContentState::new(
                &replacement.descriptor,
                true
            )),
            None
        )
        .await
        .is_err()
    );
    assert!(
        write_operation(
            &db,
            &body(b"replacement again", 3),
            false,
            &CurrentContentOperation::Replace(CurrentContentState::new(
                &replacement.descriptor,
                true
            )),
            None
        )
        .await
        .is_err()
    );
    let mut missing = appended;
    missing.descriptor.key.owner = ChatKey::new("item", "missing")?;
    assert!(
        write_operation(
            &db,
            &missing,
            false,
            &CurrentContentOperation::Append(CurrentContentState::new(&initial.descriptor, false)),
            None
        )
        .await
        .is_err()
    );
    assert!(validate_content(&db, &replacement).await?.unwrap().sealed);
    Ok(())
}

#[tokio::test]
async fn incremental_content_rejects_missing_gap_overlap_and_invalid_chunks() -> Result<()> {
    for damage in [
        "DELETE FROM conversation_content_chunks WHERE byte_offset=4",
        "UPDATE conversation_content_chunks SET byte_offset=3 WHERE byte_offset=2",
        // Same total length and same final end as the valid chunks: overlap and gap cancel.
        "UPDATE conversation_content_chunks SET byte_offset=1 WHERE byte_offset=2",
        "UPDATE conversation_content_chunks SET data=X'' WHERE byte_offset=2",
        "UPDATE conversation_content_chunks SET data=zeroblob(65537) WHERE byte_offset=2",
    ] {
        let (_dir, db) = super::super::tests::fixture().await?;
        let initial = body(b"abcdef", 1);
        write_operation(&db, &initial, false, &CurrentContentOperation::Create, None).await?;
        db.execute_unprepared("DELETE FROM conversation_content_chunks")
            .await?;
        for (offset, bytes) in [(0i64, b"ab"), (2, b"cd"), (4, b"ef")] {
            db.execute_raw(statement(
                "INSERT INTO conversation_content_chunks(owner_key,content_key,byte_offset,data) VALUES(?,?,?,?)",
                vec![initial.descriptor.key.owner.as_str().into(), "body".into(), offset.into(), bytes.to_vec().into()],
            )).await?;
        }
        db.execute_unprepared(damage).await?;
        let result = write_operation(
            &db,
            &body(b"abcdefg", 1),
            false,
            &CurrentContentOperation::Append(CurrentContentState::new(&initial.descriptor, false)),
            None,
        )
        .await;
        assert!(result.is_err(), "accepted damaged chunks: {damage}");
        assert_eq!(
            read_manifest(&db, &initial.descriptor.key)
                .await?
                .unwrap()
                .0
                .byte_length,
            6
        );
    }
    Ok(())
}

#[tokio::test]
async fn incremental_content_defers_equal_length_tampering_to_full_boundaries() -> Result<()> {
    let (_dir, db) = super::super::tests::fixture().await?;
    let initial = body(b"abcdef", 1);
    write_operation(&db, &initial, false, &CurrentContentOperation::Create, None).await?;
    db.execute_unprepared("UPDATE conversation_content_chunks SET data=X'414263646566'")
        .await?;
    let appended = body(b"abcdefg", 1);
    write_operation(
        &db,
        &appended,
        false,
        &CurrentContentOperation::Append(CurrentContentState::new(&initial.descriptor, false)),
        None,
    )
    .await?;
    assert!(validate_content(&db, &appended).await.is_err());
    assert!(write_content(&db, &appended, false).await.is_err());
    assert!(
        write_operation(
            &db,
            &appended,
            true,
            &CurrentContentOperation::Seal(CurrentContentState::new(&appended.descriptor, false)),
            None
        )
        .await
        .is_err()
    );
    Ok(())
}

#[tokio::test]
async fn incremental_content_explicit_takeover_conditional_zero_and_rollback_retry() -> Result<()> {
    let (_dir, db) = super::super::tests::fixture().await?;
    let initial = body(b"abcdef", 1);
    write_content(&db, &initial, false).await?;
    let expected = CurrentContentState::new(&initial.descriptor, false);
    assert!(
        write_operation(
            &db,
            &body(b"not the prefix", 1),
            false,
            &CurrentContentOperation::Takeover(expected.clone()),
            None
        )
        .await
        .is_err()
    );
    let appended = body(b"abcdefg", 1);
    db.execute_unprepared(
        "CREATE TRIGGER lose_content_cas BEFORE UPDATE ON conversation_contents
        BEGIN SELECT RAISE(IGNORE); END",
    )
    .await?;
    let error = write_operation(
        &db,
        &appended,
        false,
        &CurrentContentOperation::Takeover(expected.clone()),
        None,
    )
    .await
    .unwrap_err();
    assert!(error.to_string().contains("conditional update"));
    db.execute_unprepared("DROP TRIGGER lose_content_cas")
        .await?;
    let tx = db.begin().await?;
    write_operation(
        &tx,
        &appended,
        false,
        &CurrentContentOperation::Takeover(expected.clone()),
        None,
    )
    .await?;
    tx.rollback().await?;
    assert_eq!(
        read_manifest(&db, &initial.descriptor.key)
            .await?
            .unwrap()
            .0
            .byte_length,
        6
    );
    write_operation(
        &db,
        &appended,
        false,
        &CurrentContentOperation::Takeover(expected),
        None,
    )
    .await?;
    // Durable replay verifies all bytes, not a second attempt to execute the old CAS.
    write_content(&db, &appended, false).await?;
    assert!(
        write_operation(
            &db,
            &appended,
            false,
            &CurrentContentOperation::Append(CurrentContentState::new(&initial.descriptor, false)),
            None
        )
        .await
        .is_err()
    );
    Ok(())
}

#[tokio::test]
async fn incremental_content_same_effect_completion_uses_full_validation_without_reopening()
-> Result<()> {
    let (_dir, db) = super::super::tests::fixture().await?;
    let initial = body(b"abc", 1);
    write_operation(&db, &initial, false, &CurrentContentOperation::Create, None).await?;
    let completed = Arc::new(body(b"abcd", 1));
    let mut item = ChatItem::complete(
        ChatDraft::new("incremental", "conversation", Arc::from(b"{}".as_slice())),
        1,
    );
    item.contents = Arc::new(ChatContents::from([(
        completed.descriptor.key.clone(),
        completed.clone(),
    )]));
    let mut prepared = PreparedCurrent::new(
        FrozenCurrentProjection::new(pl_protocol::CurrentProjection::empty(
            2,
            pl_protocol::ThreadStatus::Idle,
        )),
        Arc::from([]),
        Arc::from([CurrentContentWrite {
            content: completed.clone(),
            sealed: false,
        }]),
    );
    prepared.body_operations = Some(Arc::from([CurrentContentOperation::Append(
        CurrentContentState::new(&initial.descriptor, false),
    )]));
    let tx = db.begin().await?;
    super::super::append_records(&tx, [&item], true).await?;
    assert!(
        current::apply_changes(&tx, 2, &prepared, &[])
            .await
            .is_err(),
        "an arbitrary sealed key must not authorize the completion handoff"
    );
    let operation = &prepared.body_operations.as_ref().unwrap()[0];
    assert!(
        write_operation(&tx, &body(b"abce", 1), false, operation, Some(&completed))
            .await
            .is_err()
    );
    current::apply_changes(&tx, 2, &prepared, &[Arc::new(item)]).await?;
    current::write_head(&tx, &prepared).await?;
    current::verify(&tx, &prepared).await?;
    assert!(
        read_manifest(&tx, &completed.descriptor.key)
            .await?
            .unwrap()
            .0
            .sealed
    );
    tx.commit().await?;
    Ok(())
}

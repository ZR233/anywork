use super::*;
use crate::studio::storage::history::conversation::current::SavedCurrentContent;

fn active(id: &str, block: Arc<ContentBlock>, ordinal: u64) -> ActiveText {
    (id.into(), BodyKey::Body, block, ordinal, None)
}

async fn commit_current_cut(
    history: &crate::studio::storage::history::HistoryStore,
    current: &PreparedCurrent,
) -> Result<()> {
    use crate::studio::storage::history::EffectCommit;
    history
        .commit_effect(
            current.projection().source_effect_seq,
            EffectCommit {
                items: &[],
                completions: &[],
                current,
                rolled_back_turns: &Default::default(),
                identities: &[],
                messages: &[],
                receipts: &[],
                tasks: &[],
                deliveries: &[],
                delivery_repairs: &[],
                attempt: None,
            },
        )
        .await
}

#[tokio::test]
async fn durable_current_replay_validates_unchanged_bodies_for_empty_and_partial_deltas()
-> Result<()> {
    use crate::studio::storage::history::HistoryStore;
    use sea_orm::{ConnectionTrait, Database, DbBackend, Statement};

    for change_b in [false, true] {
        for missing_chunk in [false, true] {
            let dir = tempfile::tempdir()?;
            let path = dir.path().join("history.sqlite");
            let history = HistoryStore::open(&path, "replay-current").await?;
            history.prepare_write().await?;
            let mut owner = CurrentOwner::default();
            owner.bind(history.conversation_database_id().await?.unwrap())?;
            let thread = Thread::placeholder("replay-current");
            let state = ThreadSnapshot::default();
            let a = ContentBlock::from_text("alpha unchanged");
            let b = ContentBlock::from_text("bravo");
            let (first, _) = owner.freeze(
                &thread,
                &state,
                1,
                [active("a", a.clone(), 1), active("b", b.clone(), 2)],
            )?;
            commit_current_cut(&history, &first).await?;
            let a_key = first
                .contents
                .iter()
                .find(|write| {
                    write.content.descriptor.key.owner
                        == content_owner_key(&ContentOwner::Item {
                            item_id: "a".into(),
                        })
                        .unwrap()
                })
                .unwrap()
                .content
                .descriptor
                .key
                .clone();
            let b = if change_b {
                ContentBlock::append(&b, " changed")
            } else {
                b
            };
            let (second, cut) =
                owner.freeze(&thread, &state, 2, [active("a", a, 1), active("b", b, 2)])?;
            assert_eq!(second.contents.len(), usize::from(change_b));
            assert!(second.references.is_empty());
            assert!(
                Arc::ptr_eq(second.replay_current.as_ref().unwrap(), &cut),
                "replay must borrow the original complete frozen cut, not build another map"
            );
            assert_eq!(cut.contents().len(), 2);
            // Persist the latest effect but retain exactly the same frozen material as a caller
            // whose ACK was lost. Repeating commit_effect takes HistoryStore's durable branch.
            commit_current_cut(&history, &second).await?;
            assert_eq!(history.watermark().await?, 2);
            commit_current_cut(&history, &second).await?;
            let db = Database::connect(format!("sqlite://{}?mode=rw", path.display())).await?;
            if missing_chunk {
                db.execute_raw(Statement::from_sql_and_values(
                    DbBackend::Sqlite,
                    "DELETE FROM conversation_content_chunks WHERE owner_key=? AND content_key=?",
                    vec![a_key.owner.as_str().into(), a_key.key.clone().into()],
                ))
                .await?;
            } else {
                assert_eq!(b"ALPHA UNCHANGED".len(), "alpha unchanged".len());
                db.execute_raw(Statement::from_sql_and_values(DbBackend::Sqlite,
                    "UPDATE conversation_content_chunks SET data=? WHERE owner_key=? AND content_key=? AND byte_offset=0",
                    vec![b"ALPHA UNCHANGED".to_vec().into(), a_key.owner.as_str().into(), a_key.key.clone().into()],
                )).await?;
            }
            let error = commit_current_cut(&history, &second).await.unwrap_err();
            let error = format!("{error:#}");
            let expected = if missing_chunk {
                "missing chunks"
            } else {
                "byte prefix changed"
            };
            assert!(
                error.contains(expected),
                "partial_delta={change_b}, missing_chunk={missing_chunk}: {error}"
            );
            assert_eq!(
                history.watermark().await?,
                2,
                "failed replay must not rewrite the effect"
            );
            db.close().await?;
            history.close_for_deletion().await?;
        }
    }
    Ok(())
}

#[test]
fn incremental_content_preparation_proves_shared_prefix_or_requires_replacement() -> Result<()> {
    let mut owner = CurrentOwner::default();
    owner.bind("database".into())?;
    let prefix = ContentBlock::from_text("prefix");
    owner.freeze(
        &Thread::placeholder("thread"),
        &ThreadSnapshot::default(),
        1,
        [active("a", prefix.clone(), 1)],
    )?;
    let previous = owner.prepared_contents.values().next().unwrap();
    let appended = ContentBlock::append(&prefix, " delta");
    let mut descriptor = previous.descriptor.clone();
    descriptor.byte_length = appended.len() as u64;
    let valid = CurrentContent {
        descriptor: descriptor.clone(),
        block: appended,
        indexed: OnceLock::new(),
    };
    assert!(matches!(
        previous.operation(&valid, false)?,
        CurrentContentOperation::Append(_)
    ));
    let unrelated = CurrentContent {
        descriptor,
        block: ContentBlock::from_text("not a prefix"),
        indexed: OnceLock::new(),
    };
    assert!(
        previous.operation(&unrelated, false).is_err(),
        "generation/length alone must never authorize an append"
    );
    let mut replaced = unrelated;
    replaced.descriptor.generation += 1;
    assert!(matches!(
        previous.operation(&replaced, false)?,
        CurrentContentOperation::Replace(_)
    ));
    let mut metadata_only = previous.clone();
    metadata_only.content = None;
    assert!(matches!(
        metadata_only.operation(&valid, false)?,
        CurrentContentOperation::Takeover(_)
    ));
    Ok(())
}

#[test]
fn reliable_current_delta_ignores_observation_and_advances_before_ack() -> Result<()> {
    let mut owner = CurrentOwner::default();
    owner.bind("database".into())?;
    let thread = Thread::placeholder("thread");
    let state = ThreadSnapshot::default();
    let a = ContentBlock::from_text("first");
    let b = ContentBlock::from_text("withdrawn");
    let initial = vec![active("a", a.clone(), 1), active("b", b, 2)];
    owner.observe(&thread, &state, 1, initial.clone())?;
    let (first, _) = owner.freeze(&thread, &state, 1, initial)?;
    assert_eq!(
        first.contents.len(),
        2,
        "observation is not a reliable seed"
    );
    assert!(
        first
            .body_operations
            .as_ref()
            .unwrap()
            .iter()
            .all(|operation| matches!(operation, CurrentContentOperation::Create))
    );
    assert_eq!(first.references.len(), 2);
    let withdrawn = first
        .contents
        .iter()
        .find(|write| {
            write.content.descriptor.key.owner
                == content_owner_key(&ContentOwner::Item {
                    item_id: "b".into(),
                })
                .unwrap()
        })
        .unwrap()
        .content
        .descriptor
        .clone();
    let appended = ContentBlock::append(&a, " more");
    let next = vec![active("a", appended.clone(), 1)];
    owner.observe(&thread, &state, 1, next.clone())?;
    let (second, _) = owner.freeze(&thread, &state, 2, next.clone())?;
    assert_eq!(second.contents.len(), 1);
    assert!(matches!(
        second.body_operations.as_ref().unwrap()[0],
        CurrentContentOperation::Append(_)
    ));
    assert!(
        second.references.is_empty(),
        "an unchanged identity is already qualified"
    );
    assert_eq!(second.retirements.len(), 1);
    assert_eq!(second.retirements[0].key, withdrawn.key);
    assert_eq!(second.retirements[0].generation, withdrawn.generation);
    assert!(second.retirements[0].only_unsealed);
    assert!(second.changes.iter().any(|change| matches!(change,
        CurrentEntryChange::Remove { collection, entry_id }
        if collection == "members" && entry_id == "b")));
    // No writer or ACK has run: the next contiguous preparation already uses the frozen cut.
    let (third, _) = owner.freeze(&thread, &state, 3, next)?;
    assert!(third.contents.is_empty());
    assert!(third.references.is_empty());
    assert!(third.retirements.is_empty());
    assert!(third.changes.is_empty());
    // The earlier frozen write remains exactly the same material for retries.
    assert_eq!(
        second.contents[0].content.data.range(0, 32)?.as_bytes(),
        b"first more"
    );
    assert_eq!(
        first.contents[0].content.data.range(0, 32)?.as_bytes(),
        b"first"
    );

    let replacement = ContentBlock::from_text("replacement");
    let (fourth, _) = owner.freeze(&thread, &state, 4, [active("a", replacement, 1)])?;
    assert_eq!(fourth.contents.len(), 1);
    assert!(matches!(
        fourth.body_operations.as_ref().unwrap()[0],
        CurrentContentOperation::Replace(_)
    ));
    assert_eq!(
        fourth.contents[0].content.descriptor.generation,
        second.contents[0].content.descriptor.generation + 1
    );
    assert!(fourth.references.is_empty());
    assert!(fourth.retirements.is_empty());
    assert!(owner.retained_bytes() > third.operation_bytes());
    Ok(())
}

#[test]
fn reliable_current_delta_failed_freeze_does_not_advance_collections_or_bodies() -> Result<()> {
    let mut owner = CurrentOwner::default();
    owner.bind("database".into())?;
    let thread = Thread::placeholder("thread");
    let state = ThreadSnapshot::default();
    // Qualification encoding fails after project has produced the new collection cut.
    let item = ThreadItem::new(
        "bad-reference".into(),
        thread.id.clone(),
        "turn".into(),
        1,
        1,
        1,
        1,
        ThreadItemState::Text(ThreadTextItem::new(
            ThreadTextChannel::Final,
            "body".into(),
            Vec::new(),
            ThreadContentLifecycle::streaming(),
        )),
    );
    let mut atom = crate::studio::runtime::chat_item::atom(&item);
    atom.contents = vec![ChatAtomContent {
        role: ChatContentRole::Body,
        reference: ContentRef {
            database_id: "database".into(),
            target: ContentTarget::Body {
                owner: ContentOwner::Current {
                    domain: String::new(),
                    id: "invalid".into(),
                    revision: 1,
                },
                key: "body".into(),
            },
        },
    }];
    owner.provenance(Vec::new(), vec![atom]);
    let body = ContentBlock::from_text("must still be written on retry");
    let active = vec![active("a", body, 1)];
    assert!(owner.freeze(&thread, &state, 1, active.clone()).is_err());
    assert!(owner.prepared_contents.is_empty());
    assert!(owner.prepared_collections.is_empty());
    assert!(owner.prepared_references.is_empty());
    owner.provenance(Vec::new(), Vec::new());
    let (retry, _) = owner.freeze(&thread, &state, 1, active)?;
    assert_eq!(retry.contents.len(), 1);
    assert_eq!(retry.references.len(), 1);
    assert!(retry.changes.iter().any(|change| matches!(change,
        CurrentEntryChange::Put(entry) if entry.collection == "members")));
    Ok(())
}

#[test]
fn reliable_current_delta_seeds_saved_generation_length_and_withdrawn_ownership() -> Result<()> {
    let mut original = CurrentOwner::default();
    original.bind("database".into())?;
    let thread = Thread::placeholder("thread");
    let state = ThreadSnapshot::default();
    let first = ContentBlock::from_text("old");
    original.freeze(&thread, &state, 1, [active("a", first, 1)])?;
    let replacement = ContentBlock::from_text("restored generation two");
    let (_, saved_state) = original.freeze(&thread, &state, 2, [active("a", replacement, 1)])?;
    let descriptor = saved_state
        .contents
        .values()
        .next()
        .unwrap()
        .descriptor
        .clone();
    assert_eq!(descriptor.generation, 2);
    let saved = || {
        let mut projection = saved_state.projection().clone();
        projection.collections.push(CurrentCollectionRef {
            database_id: "database".into(),
            collection: "withdrawn-collection".into(),
            revision: 2,
        });
        SavedCurrent {
            projection,
            contents: BTreeMap::from([(
                descriptor.key.clone(),
                SavedCurrentContent {
                    descriptor: descriptor.clone(),
                    sealed: false,
                },
            )]),
        }
    };
    let mut restored = CurrentOwner::default();
    restored.bind("database".into())?;
    restored.restore_generation(descriptor.key.clone(), descriptor.generation)?;
    let block = ContentBlock::from_text("restored generation two");
    let current = vec![active("a", block, 1)];
    let snapshot = restored.observe(&thread, &state, 2, current.clone())?;
    restored.restore_prepared(saved(), &snapshot)?;
    let (unchanged, _) = restored.freeze(&thread, &state, 3, current)?;
    assert!(
        unchanged.contents.is_empty(),
        "restored saved content is already prepared"
    );
    assert!(unchanged.references.is_empty());
    assert!(unchanged.changes.iter().any(|change| matches!(change,
        CurrentEntryChange::Clear { collection } if collection == "withdrawn-collection")));
    let (withdrawn, _) = restored.freeze(&thread, &state, 4, [])?;
    assert_eq!(withdrawn.retirements.len(), 1);
    assert_eq!(withdrawn.retirements[0].generation, 2);
    assert_eq!(withdrawn.retirements[0].key, descriptor.key);

    // A canonical terminal may mean no active body is restored. Its saved identity must still
    // survive as metadata so the first reliable effect can retire precisely that incarnation.
    let mut terminal = CurrentOwner::default();
    terminal.bind("database".into())?;
    let snapshot = terminal.observe(&thread, &state, 2, [])?;
    terminal.restore_prepared(saved(), &snapshot)?;
    let (first_effect, _) = terminal.freeze(&thread, &state, 3, [])?;
    assert_eq!(first_effect.retirements.len(), 1);
    assert_eq!(first_effect.retirements[0].key, descriptor.key);
    assert_eq!(
        first_effect.retirements[0].generation,
        descriptor.generation
    );
    Ok(())
}

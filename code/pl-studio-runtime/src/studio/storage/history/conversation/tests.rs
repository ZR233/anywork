use super::*;
use pl_core::chat::{
    ChatContent, ChatContentKey, ChatContents, ChatDraft, ChatError, ChatQuery, ContentData,
    ContentDescriptor, ContentReadRequest, ContentRef, ReadDemand, TimelineEpoch,
};
use sea_orm::{Database, DatabaseConnection, TransactionTrait};

pub(super) struct Budget;
impl ChatBudget for Budget {
    fn fixed_bytes(&self) -> usize {
        0
    }
    fn item_bytes(&self, h: &ChatItemHeader, mode: PayloadMode) -> usize {
        match mode {
            PayloadMode::Inline => 64 + h.byte_length as usize,
            PayloadMode::Deferred => 64,
        }
    }
    fn manifest_bytes(&self, _: &ContentDescriptor) -> usize {
        128
    }
}

async fn fixture() -> Result<(tempfile::TempDir, DatabaseConnection)> {
    let dir = tempfile::tempdir()?;
    let path = dir.path().join("history.sqlite");
    let mut options = sea_orm::ConnectOptions::new(format!("sqlite://{}?mode=rwc", path.display()));
    options
        .max_connections(1)
        .min_connections(1)
        .sqlx_logging(false);
    let db = Database::connect(options).await?;
    db.execute_unprepared(
        "CREATE TABLE history_meta(id INTEGER PRIMARY KEY,applied_write_seq INTEGER NOT NULL);
         INSERT INTO history_meta VALUES(1,0);",
    )
    .await?;
    db.execute_unprepared(migration::CREATE_SCHEMA).await?;
    db.execute_unprepared(
        "ALTER TABLE conversation_items ADD COLUMN metadata BLOB NOT NULL DEFAULT X''",
    )
    .await?;
    db.execute_unprepared(sources::CREATE_SCHEMA).await?;
    Ok((dir, db))
}

fn item(seq: u64, class: &str, payload: &[u8]) -> ChatItem {
    ChatItem::complete(
        ChatDraft::new(format!("item:{seq}"), class, Arc::from(payload)),
        seq,
    )
}

pub(super) fn metadata(id: &str) -> Arc<[u8]> {
    serde_json::to_vec(&pl_protocol::ChatAtom {
        id: id.into(),
        completion_item_id: Some(id.into()),
        completion_seq: None,
        source_state: None,
        source: pl_protocol::ChatSourceId::Receipt {
            receipt_id: id.into(),
        },
        source_order: None,
        kind: pl_protocol::ChatAtomKind::Unknown,
        delivery: pl_protocol::ChatDeliveryKind::Independent,
        lifecycle: pl_protocol::ChatAtomLifecycle::Terminal {
            started: None,
            ended: None,
            outcome: pl_protocol::ChatTerminalOutcome::Completed,
        },
        turn_id: None,
        attempt_id: None,
        tool: None,
        wait: None,
        text_channel: None,
        started_at: None,
        finished_at: None,
        contents: vec![],
        payload: None,
    })
    .unwrap()
    .into()
}

#[tokio::test]
async fn metadata_budget_deferred_keyset_and_immutable_blob_conflicts() -> Result<()> {
    struct MetadataBudget;
    impl ChatBudget for MetadataBudget {
        fn fixed_bytes(&self) -> usize {
            0
        }
        fn item_bytes(&self, header: &ChatItemHeader, mode: PayloadMode) -> usize {
            header.metadata.len()
                + match mode {
                    PayloadMode::Inline => 64 + header.byte_length as usize,
                    PayloadMode::Deferred => 64,
                }
        }
        fn manifest_bytes(&self, _: &ContentDescriptor) -> usize {
            unreachable!()
        }
    }
    let (_dir, db) = fixture().await?;
    let mut first = item(1, "conversation", &[255; 256 * 1024]);
    first.header.metadata = metadata("item:1");
    let mut second = item(2, "conversation", b"opaque neighbour");
    second.header.metadata = metadata("item:2");
    append_records(&db, [&first, &second], true).await?;
    append_records(&db, [&first, &second], false).await?;
    let mut changed = first.clone();
    changed.header.metadata = Arc::from(b"same payload, different metadata".as_slice());
    assert!(append_records(&db, [&changed], false).await.is_err());
    let exact = MetadataBudget.item_bytes(&first.header, PayloadMode::Deferred);
    let request = ChatHistoryRequest {
        query: Some(ChatQuery::new("conversation", None)),
        after: 0,
        before: Some(2),
        ceiling: 2,
        demand: ReadDemand::new(2, exact),
    };
    let selected = page(&db, &request, &MetadataBudget, false).await?;
    assert!(selected.exhausted);
    assert_eq!(selected.items.len(), 1);
    assert_eq!(selected.items[0].header, first.header);
    assert!(matches!(
        selected.items[0].payload,
        PayloadData::Deferred {
            byte_length: 262144,
            ..
        }
    ));
    let under = ChatHistoryRequest {
        demand: ReadDemand::new(2, exact - 1),
        ..request.clone()
    };
    let selected = page(&db, &under, &MetadataBudget, false).await?;
    assert!(selected.items.is_empty());
    assert!(!selected.exhausted, "byte truncation is not EOF");
    let remaining = ChatHistoryRequest {
        after: 1,
        before: None,
        demand: ReadDemand::new(2, 4096),
        ..request
    };
    let selected = page(&db, &remaining, &MetadataBudget, true).await?;
    assert_eq!(selected.items.len(), 1);
    assert_eq!(selected.items[0].header.metadata, second.header.metadata);
    assert!(
        matches!(&selected.items[0].payload, PayloadData::Inline(bytes) if bytes.as_ref()==b"opaque neighbour")
    );
    Ok(())
}

#[tokio::test]
async fn demand_selects_indexed_scope_and_defers_oversized_payload() -> Result<()> {
    let (_dir, db) = fixture().await?;
    let a = item(1, "conversation", b"small");
    let mut b = item(2, "conversation", &vec![b'x'; 128 * 1024]);
    b.header.parent_id = Some(ChatKey::new("turn", "id:with:colons")?);
    let c = item(3, "diagnostic", &vec![b'y'; 128 * 1024]);
    append_records(&db, [&a, &b, &c], true).await?;
    let request = ChatHistoryRequest {
        query: Some(ChatQuery::new("conversation", None)),
        after: 0,
        before: None,
        ceiling: 3,
        demand: ReadDemand::new(2, 200),
    };
    let selected_page = page(&db, &request, &Budget, false).await?;
    assert_eq!(
        selected_page
            .items
            .iter()
            .map(|item| item.header.append_seq)
            .collect::<Vec<_>>(),
        [1, 2]
    );
    assert!(matches!(
        selected_page.items[0].payload,
        PayloadData::Inline(_)
    ));
    assert!(matches!(
        selected_page.items[1].payload,
        PayloadData::Deferred { .. }
    ));
    assert!(
        !selected_page.exhausted,
        "exact demand does not issue an extra existence probe"
    );
    let children = ChatHistoryRequest {
        query: Some(ChatQuery::new(
            "conversation",
            Some(ChatKey::new("turn", "id:with:colons")?),
        )),
        demand: ReadDemand::new(4, 200),
        ..request.clone()
    };
    let selected = page(&db, &children, &Budget, false).await?;
    assert_eq!(selected.items.len(), 1);
    assert_eq!(selected.items[0].header.item_id, "item:2");
    assert!(selected.exhausted);
    let capped = ChatHistoryRequest {
        ceiling: 1,
        ..request
    };
    assert_eq!(
        page(&db, &capped, &Budget, false).await?.items[0]
            .header
            .append_seq,
        1
    );
    Ok(())
}

#[tokio::test]
async fn cold_scope_budget_fits_exact_envelope_and_rejects_one_byte_less() -> Result<()> {
    use pl_protocol::{
        ChatAtom, ChatBatch, ChatEntry, ChatPlacement, ChatScope, ContentTarget,
        CurrentCollectionRef, CurrentProjection, PayloadData as WirePayload,
    };

    struct ColdBudget {
        database_id: String,
        fixed: usize,
    }
    impl ChatBudget for ColdBudget {
        fn fixed_bytes(&self) -> usize {
            self.fixed
        }
        fn item_bytes(&self, header: &ChatItemHeader, mode: PayloadMode) -> usize {
            let payload = match mode {
                PayloadMode::Inline => WirePayload::Inline { bytes: Vec::new() },
                PayloadMode::Deferred => WirePayload::Deferred {
                    reference: pl_protocol::ContentRef {
                        database_id: self.database_id.clone(),
                        target: ContentTarget::ItemPayload {
                            item_id: header.item_id.clone(),
                        },
                    },
                    byte_length: header.byte_length,
                },
            };
            let mut atom: ChatAtom = serde_json::from_slice(&header.metadata).unwrap();
            atom.completion_seq = Some(header.append_seq);
            atom.source_state = Some(pl_protocol::ChatSourceState {
                source: atom.source.clone(),
                lifecycle: pl_protocol::ChatSourceLifecycle::Unknown,
                started: None,
                ended: None,
            });
            atom.payload = Some(payload);
            let base = serde_json::to_vec(&ChatEntry::Atom(Box::new(atom)))
                .unwrap()
                .len();
            if mode == PayloadMode::Inline && header.byte_length != 0 {
                // Each JSON byte uses at most three digits, plus inter-byte commas.
                base + header.byte_length as usize * 4 - 1
            } else {
                base
            }
        }
        fn manifest_bytes(&self, _: &ContentDescriptor) -> usize {
            unreachable!("cold pages do not read manifests")
        }
    }
    fn wire_batch(
        database_id: &str,
        current: Option<CurrentProjection>,
        items: &[ChatPageItem],
    ) -> ChatBatch {
        ChatBatch {
            placement: ChatPlacement::Set,
            before: None,
            current,
            entries: items
                .iter()
                .map(|item| {
                    let mut atom: ChatAtom = serde_json::from_slice(&item.header.metadata).unwrap();
                    atom.completion_seq = Some(item.header.append_seq);
                    atom.source_state = Some(pl_protocol::ChatSourceState {
                        source: atom.source.clone(),
                        lifecycle: pl_protocol::ChatSourceLifecycle::Unknown,
                        started: None,
                        ended: None,
                    });
                    atom.payload = Some(match &item.payload {
                        PayloadData::Inline(bytes) => WirePayload::Inline {
                            bytes: bytes.to_vec(),
                        },
                        PayloadData::Deferred {
                            item_id,
                            byte_length,
                        } => WirePayload::Deferred {
                            reference: pl_protocol::ContentRef {
                                database_id: database_id.into(),
                                target: ContentTarget::ItemPayload {
                                    item_id: item_id.clone(),
                                },
                            },
                            byte_length: *byte_length,
                        },
                    });
                    ChatEntry::Atom(Box::new(atom))
                })
                .collect(),
        }
    }

    let dir = tempfile::tempdir()?;
    let store =
        super::super::HistoryStore::open(&dir.path().join("history.sqlite"), "cold-budget").await?;
    store.prepare_write().await?;
    let database_id = store.conversation_database_id().await?.unwrap();
    let parent = ChatKey::new("turn", "target:parent")?;
    let mut main_item = item(1, "conversation", &[255; 2048]);
    let mut child_item = item(2, "conversation", &[255; 2048]);
    child_item.header.parent_id = Some(parent.clone());
    let mut other_child = item(3, "conversation", &[255; 2048]);
    other_child.header.parent_id = Some(ChatKey::new("turn", "other:parent")?);
    for item in [&mut main_item, &mut child_item, &mut other_child] {
        item.header.metadata = metadata(&item.header.item_id);
    }
    let mut projection = CurrentProjection::empty(0, pl_protocol::ThreadStatus::Idle);
    projection.collections.push(CurrentCollectionRef {
        database_id: database_id.clone(),
        collection: "无关集合".repeat(1024),
        revision: 1,
    });
    let writer = store.writer().await?;
    let tx = writer.db.begin().await?;
    append_records(&tx, [&main_item, &child_item, &other_child], true).await?;
    tx.execute_raw(statement(
        "UPDATE conversation_view_state SET payload=? WHERE singleton_id=1",
        vec![serde_json::to_vec(&projection)?.into()],
    ))
    .await?;
    tx.commit().await?;
    let budget = ColdBudget {
        fixed: wire_batch(&database_id, None, &[]).encoded_len()?,
        database_id: database_id.clone(),
    };
    for (scope, target) in [
        (
            ChatScope::Children {
                parent_id: parent.as_str().into(),
            },
            &child_item,
        ),
        (ChatScope::Main, &other_child),
    ] {
        let main = scope == ChatScope::Main;
        let expected = ChatPageItem {
            header: target.header.clone(),
            payload: PayloadData::Deferred {
                item_id: target.header.item_id.clone(),
                byte_length: target.header.byte_length,
            },
        };
        let minimum = wire_batch(
            &database_id,
            main.then(|| projection.clone()),
            std::slice::from_ref(&expected),
        )
        .encoded_len()?;
        if !main {
            assert!(
                serde_json::to_vec(&projection)?.len() > minimum,
                "the unrelated Main current must exceed the entire Children demand"
            );
        }
        let query = ChatQuery::new(
            scope.query_class(),
            scope
                .parent_id()
                .map(|parent| ChatKey::from_encoded(parent.to_owned()))
                .transpose()?,
        );
        let cold = store
            .cold_conversation(query.clone(), ReadDemand::new(2, minimum), &budget)
            .await?
            .context("existing cold database")?;
        assert_eq!(cold.database_id, database_id);
        assert_eq!(cold.head, 3);
        assert_eq!(cold.current, projection);
        assert_eq!(cold.page.exhausted, !main);
        assert_eq!(cold.page.items, [expected]);
        let actual = wire_batch(
            &cold.database_id,
            main.then_some(cold.current),
            &cold.page.items,
        );
        actual.validate_for(&scope)?;
        assert_eq!(
            actual.entries.len(),
            1,
            "page source annotation must not create a second entry"
        );
        assert!(matches!(&actual.entries[0], ChatEntry::Atom(atom) if atom.source_state.is_some()));
        assert_eq!(actual.encoded_len()?, minimum);
        assert!(
            actual.encoded_len()? <= minimum,
            "actual scope delivery must stay within demand"
        );
        let error = store
            .cold_conversation(query, ReadDemand::new(2, minimum - 1), &budget)
            .await
            .err()
            .context("one byte less must reject the target envelope")?;
        assert!(
            matches!(
                error.downcast_ref::<ChatError>(),
                Some(ChatError::InvalidDemand(_))
            ),
            "{scope:?}: {error:#}"
        );
        eprintln!(
            "cold budget {scope:?}: exact={minimum}, actual={}, one-byte-less=InvalidDemand",
            actual.encoded_len()?
        );
    }
    Ok(())
}

#[tokio::test]
async fn payload_and_body_ranges_cross_chunks_without_reading_whole_values() -> Result<()> {
    let (_dir, db) = fixture().await?;
    let bytes: Arc<[u8]> = Arc::from((0..200_000).map(|i| (i % 251) as u8).collect::<Vec<_>>());
    let mut record = item(1, "conversation", &bytes);
    let key = ChatContentKey {
        owner: ChatKey::new("item", "item:1")?,
        key: "body".into(),
    };
    record.contents = Arc::new(ChatContents::from([(
        key.clone(),
        Arc::new(ChatContent {
            descriptor: ContentDescriptor {
                key: key.clone(),
                byte_length: bytes.len() as u64,
                generation: 7,
                media_type: None,
            },
            data: ContentData::Bytes(bytes.clone()),
        }),
    )]));
    append_records(&db, [&record], true).await?;
    let manifest = list_contents(
        &db,
        &pl_core::chat::ContentManifestRequest {
            epoch: TimelineEpoch::new("test")?,
            item_id: "item:1".into(),
            after: None,
            demand: ReadDemand::new(4, 512),
        },
        &Budget,
    )
    .await?;
    assert_eq!(manifest.entries.len(), 1);
    assert_eq!(manifest.entries[0].key, key);
    assert_eq!(manifest.entries[0].generation, 7);
    assert!(manifest.next.is_none());
    for reference in [
        ContentRef::ItemPayload("item:1".into()),
        ContentRef::Body(key.clone()),
    ] {
        let request = ContentReadRequest {
            epoch: TimelineEpoch::new("test")?,
            reference,
            offset: 65_531,
            max_bytes: 17,
            generation: None,
        };
        let window = read_content(&db, &request).await?;
        assert_eq!(window.bytes.as_bytes(), &bytes[65_531..65_548]);
        assert_eq!(window.offset, request.offset);
        assert_eq!(window.available_through, bytes.len() as u64);
        let eof = read_content(
            &db,
            &ContentReadRequest {
                offset: bytes.len() as u64,
                ..request.clone()
            },
        )
        .await?;
        assert!(eof.bytes.as_bytes().is_empty());
    }
    let stale = ContentReadRequest {
        epoch: TimelineEpoch::new("test")?,
        reference: ContentRef::Body(key.clone()),
        offset: 0,
        max_bytes: 1,
        generation: Some(6),
    };
    assert!(
        matches!(
            read_content(&db, &stale)
                .await
                .unwrap_err()
                .downcast_ref::<ChatError>(),
            Some(ChatError::StaleContent)
        ),
        "stale generation must not succeed"
    );
    Ok(())
}

#[tokio::test]
async fn active_prefix_validation_compares_bytes_and_sealing_is_monotonic() -> Result<()> {
    let (_dir, db) = fixture().await?;
    let key = ChatContentKey {
        owner: ChatKey::new("item", "active")?,
        key: "body".into(),
    };
    let make = |bytes: &[u8]| ChatContent {
        descriptor: ContentDescriptor {
            key: key.clone(),
            byte_length: bytes.len() as u64,
            generation: 4,
            media_type: Some("text/plain".into()),
        },
        data: ContentData::Bytes(Arc::from(bytes)),
    };
    let first = make(b"first");
    super::content::write_content(&db, &first, false).await?;
    validate_content(&db, &first).await?;
    let request = ContentReadRequest {
        epoch: TimelineEpoch::new("active")?,
        reference: ContentRef::Body(key.clone()),
        offset: 0,
        max_bytes: 100,
        generation: Some(4),
    };
    assert!(!read_content(&db, &request).await?.sealed);
    let manifest = list_contents(
        &db,
        &pl_core::chat::ContentManifestRequest {
            epoch: TimelineEpoch::new("active")?,
            item_id: "active".into(),
            after: None,
            demand: ReadDemand::new(5, 1024),
        },
        &Budget,
    )
    .await?;
    assert_eq!(
        manifest.entries.len(),
        1,
        "active Item content does not need a completed item row"
    );
    let appended = make(b"first plus an appended tail");
    validate_content(&db, &appended).await?;
    super::content::write_content(&db, &appended, false).await?;
    let bad_prefix = make(b"FIRST plus an appended tail");
    assert!(matches!(
        validate_content(&db, &bad_prefix)
            .await
            .unwrap_err()
            .downcast_ref::<ChatError>(),
        Some(ChatError::Conflict(_))
    ));
    let shorter = make(b"fir");
    assert!(matches!(
        validate_content(&db, &shorter)
            .await
            .unwrap_err()
            .downcast_ref::<ChatError>(),
        Some(ChatError::Conflict(_))
    ));
    super::content::write_content(&db, &appended, true).await?;
    super::content::write_content(&db, &appended, false).await?;
    let window = read_content(&db, &request).await?;
    assert!(
        window.sealed,
        "an identical snapshot never reopens a sealed key"
    );
    assert_eq!(window.bytes.as_bytes(), b"first plus an appended tail");
    assert!(matches!(
        validate_content(&db, &make(b"first plus an appended tail!"))
            .await
            .unwrap_err()
            .downcast_ref::<ChatError>(),
        Some(ChatError::Conflict(_))
    ));
    db.execute_unprepared("DELETE FROM conversation_content_chunks WHERE byte_offset=5")
        .await?;
    let error = validate_content(&db, &appended).await.unwrap_err();
    assert!(
        error.downcast_ref::<ChatError>().is_none(),
        "missing durable bytes are storage damage, not a producer conflict"
    );
    let mut replaceable = first.clone();
    replaceable.descriptor.key.key = "replaceable".into();
    super::content::write_content(&db, &replaceable, false).await?;
    let old_generation = ContentReadRequest {
        reference: ContentRef::Body(replaceable.descriptor.key.clone()),
        ..request.clone()
    };
    replaceable.descriptor.generation = 5;
    replaceable.descriptor.byte_length = 3;
    replaceable.data = ContentData::Bytes(Arc::from(b"new".as_slice()));
    validate_content(&db, &replaceable).await?;
    super::content::write_content(&db, &replaceable, false).await?;
    assert!(matches!(
        read_content(&db, &old_generation)
            .await
            .unwrap_err()
            .downcast_ref::<ChatError>(),
        Some(ChatError::StaleContent)
    ));
    let replaced = read_content(
        &db,
        &ContentReadRequest {
            generation: Some(5),
            ..old_generation
        },
    )
    .await?;
    assert_eq!(replaced.bytes.as_bytes(), b"new");
    assert!(!replaced.sealed);
    Ok(())
}

#[tokio::test]
async fn current_collection_budget_reserves_qualified_cursor_before_selecting_entries() -> Result<()>
{
    use pl_protocol::{
        ContentOwner, ContentTarget, CurrentCollectionEntry, CurrentCollectionPage,
        CurrentCollectionRef, CurrentProjection, PayloadData as WirePayload,
    };

    let dir = tempfile::tempdir()?;
    let store =
        super::super::HistoryStore::open(&dir.path().join("history.sqlite"), "current-budget")
            .await?;
    store.prepare_write().await?;
    let database_id = store.conversation_database_id().await?.unwrap();
    let reference = CurrentCollectionRef {
        database_id: database_id.clone(),
        collection: "entries".into(),
        revision: 9,
    };
    let mut projection = CurrentProjection::empty(1, pl_protocol::ThreadStatus::Idle);
    projection.collections.push(reference.clone());
    let entries = [(37, "first"), (900, "second")];
    let body: Arc<[u8]> = Arc::from(vec![255; 64 * 1024]);
    let prepared = current::PreparedCurrent {
        source_changes: Arc::from([]),
        projection,
        changes: entries
            .iter()
            .map(|&(position, id)| {
                current::CurrentEntryChange::Put(current::CurrentEntryWrite {
                    collection: reference.collection.clone(),
                    position,
                    entry_id: id.into(),
                    payload: body.clone(),
                })
            })
            .collect::<Vec<_>>()
            .into(),
        contents: Arc::from([]),
    };
    let writer = store.writer().await?;
    let tx = writer.db.begin().await?;
    current::apply(&tx, 1, &prepared).await?;
    tx.execute_unprepared("UPDATE history_meta SET applied_write_seq=1 WHERE id=1")
        .await?;
    tx.commit().await?;

    let expected_entry = |position, id: &str| CurrentCollectionEntry {
        id: id.into(),
        position,
        payload: WirePayload::Deferred {
            reference: pl_protocol::ContentRef {
                database_id: database_id.clone(),
                target: ContentTarget::Body {
                    owner: ContentOwner::Current {
                        domain: "collection:entries".into(),
                        id: id.into(),
                        revision: reference.revision,
                    },
                    key: "entry".into(),
                },
            },
            byte_length: body.len() as u64,
        },
    };
    let raw_first = serde_json::to_string(&entries[0])?;
    let raw_second = serde_json::to_string(&entries[1])?;
    let prefix = "lease:\\\"".repeat(512);
    let wrapped_first = format!("{prefix}{raw_first}");
    let expected = CurrentCollectionPage {
        revision: reference.revision,
        entries: vec![expected_entry(37, "first")],
        continuation: Some(wrapped_first.clone()),
    };
    let minimum = serde_json::to_vec(&expected)?.len();
    let raw_two = CurrentCollectionPage {
        entries: vec![expected_entry(37, "first"), expected_entry(900, "second")],
        continuation: Some(raw_second.clone()),
        ..expected.clone()
    };
    assert!(
        serde_json::to_vec(&raw_two)?.len() < minimum,
        "budgeting the raw cursor would incorrectly admit both entries"
    );
    let calls = std::sync::Mutex::new(Vec::new());
    let encode = |raw: String| -> Result<String> {
        calls.lock().unwrap().push(raw.clone());
        Ok(format!("{prefix}{raw}"))
    };
    let demand = pl_protocol::ReadDemand {
        max_items: 2,
        max_bytes: u32::try_from(minimum)?,
    };
    let page = store
        .page_current(&reference, None, demand, &encode)
        .await?;
    assert_eq!(page, expected);
    assert_eq!(page.continuation.as_deref(), Some(wrapped_first.as_str()));
    assert_eq!(serde_json::to_vec(&page)?.len(), minimum);
    assert_eq!(*calls.lock().unwrap(), [raw_first.clone(), raw_second]);

    calls.lock().unwrap().clear();
    let error = store
        .page_current(
            &reference,
            None,
            pl_protocol::ReadDemand {
                max_bytes: demand.max_bytes - 1,
                ..demand
            },
            &encode,
        )
        .await
        .unwrap_err();
    assert!(matches!(
        error.downcast_ref::<ChatError>(),
        Some(ChatError::InvalidDemand(_))
    ));
    assert_eq!(*calls.lock().unwrap(), [raw_first]);

    let rejected = store
        .page_current(&reference, None, demand, &|_| {
            Err(std::io::Error::new(
                std::io::ErrorKind::PermissionDenied,
                "qualified cursor encoder rejected",
            )
            .into())
        })
        .await
        .unwrap_err();
    let original = rejected
        .downcast_ref::<std::io::Error>()
        .context("callback error type must propagate unchanged")?;
    assert_eq!(original.kind(), std::io::ErrorKind::PermissionDenied);
    assert_eq!(original.to_string(), "qualified cursor encoder rejected");
    eprintln!(
        "current qualified cursor: exact={minimum}, actual={}, one-byte-less=InvalidDemand, raw-two={}, callback=PermissionDenied",
        serde_json::to_vec(&page)?.len(),
        serde_json::to_vec(&raw_two)?.len(),
    );
    Ok(())
}

#[tokio::test]
async fn current_revision_retirement_is_stale_and_collection_pages_use_stored_positions()
-> Result<()> {
    let (_dir, db) = fixture().await?;
    let prepare = |revision, text: &[u8]| -> Result<current::PreparedCurrent> {
        let owner = pl_protocol::ContentOwner::Current {
            domain: "plan".into(),
            id: "document".into(),
            revision,
        };
        let key = ChatContentKey {
            owner: crate::studio::conversation_identity::content_owner_key(&owner)?,
            key: "document".into(),
        };
        let mut projection =
            pl_protocol::CurrentProjection::empty(revision, pl_protocol::ThreadStatus::Idle);
        projection.plan = Some(pl_protocol::CurrentPlanHead {
            revision,
            phase: pl_protocol::AgentSessionPlanPhase::default(),
            document: Some(pl_protocol::ContentRef {
                database_id: "database".into(),
                target: pl_protocol::ContentTarget::Body {
                    owner,
                    key: "document".into(),
                },
            }),
        });
        projection
            .collections
            .push(pl_protocol::CurrentCollectionRef {
                database_id: "database".into(),
                collection: "entries".into(),
                revision,
            });
        Ok(current::PreparedCurrent {
            source_changes: Arc::from([]),
            projection,
            changes: Arc::from([
                current::CurrentEntryChange::Clear {
                    collection: "entries".into(),
                },
                current::CurrentEntryChange::Put(current::CurrentEntryWrite {
                    collection: "entries".into(),
                    position: 37,
                    entry_id: "actual-position".into(),
                    payload: Arc::from(b"{\"known\":true}".as_slice()),
                }),
            ]),
            contents: Arc::from([current::CurrentContentWrite {
                content: Arc::new(ChatContent {
                    descriptor: ContentDescriptor {
                        key,
                        byte_length: text.len() as u64,
                        generation: 1,
                        media_type: Some("text/plain".into()),
                    },
                    data: ContentData::Bytes(Arc::from(text)),
                }),
                sealed: true,
            }]),
        })
    };
    let mut first = prepare(1, b"first revision")?;
    let auxiliary = ChatContentKey {
        owner: crate::studio::conversation_identity::content_owner_key(
            &pl_protocol::ContentOwner::Current {
                domain: "auxiliary".into(),
                id: "owned-document".into(),
                revision: 1,
            },
        )?,
        key: "body".into(),
    };
    let mut declared = first.contents.to_vec();
    declared.push(current::CurrentContentWrite {
        content: Arc::new(ChatContent {
            descriptor: ContentDescriptor {
                key: auxiliary.clone(),
                byte_length: 3,
                generation: 1,
                media_type: None,
            },
            data: ContentData::Bytes(Arc::from(b"aux".as_slice())),
        }),
        sealed: true,
    });
    let active_item = ChatContentKey {
        owner: ChatKey::new("item", "withdrawn-active")?,
        key: "body".into(),
    };
    declared.push(current::CurrentContentWrite {
        content: Arc::new(ChatContent {
            descriptor: ContentDescriptor {
                key: active_item.clone(),
                byte_length: 3,
                generation: 1,
                media_type: None,
            },
            data: ContentData::Bytes(Arc::from(b"run".as_slice())),
        }),
        sealed: false,
    });
    first.contents = Arc::from(declared);
    let mut completed = item(1, "conversation", b"{}");
    let sealed_item = ChatContentKey {
        owner: ChatKey::new("item", "item:1")?,
        key: "body".into(),
    };
    completed.contents = Arc::new(ChatContents::from([(
        sealed_item.clone(),
        Arc::new(ChatContent {
            descriptor: ContentDescriptor {
                key: sealed_item.clone(),
                byte_length: 4,
                generation: 1,
                media_type: None,
            },
            data: ContentData::Bytes(Arc::from(b"done".as_slice())),
        }),
    )]));
    append_records(&db, [&completed], true).await?;
    current::apply(&db, 1, &first).await?;
    db.execute_unprepared("UPDATE history_meta SET applied_write_seq=1")
        .await?;
    let request = ContentReadRequest {
        epoch: TimelineEpoch::new("current")?,
        reference: ContentRef::Body(first.contents[0].content.descriptor.key.clone()),
        offset: 0,
        max_bytes: 32,
        generation: Some(1),
    };
    assert_eq!(
        read_content(&db, &request).await?.bytes.as_bytes(),
        b"first revision"
    );
    let reference = &first.projection.collections[0];
    let page = current::page(
        &db,
        reference,
        None,
        pl_protocol::ReadDemand {
            max_items: 1,
            max_bytes: 4096,
        },
        &Ok,
    )
    .await?;
    assert_eq!(page.entries[0].position, 37);
    assert!(
        page.continuation.is_some(),
        "exactly full demand does not probe for hasOlder"
    );
    let end = current::page(
        &db,
        reference,
        page.continuation.as_deref(),
        pl_protocol::ReadDemand {
            max_items: 1,
            max_bytes: 4096,
        },
        &Ok,
    )
    .await?;
    assert!(end.entries.is_empty());
    assert!(end.continuation.is_none());
    let second = prepare(2, b"second revision")?;
    current::apply(&db, 2, &second).await?;
    db.execute_unprepared("UPDATE history_meta SET applied_write_seq=2")
        .await?;
    assert!(matches!(
        read_content(&db, &request)
            .await
            .unwrap_err()
            .downcast_ref::<ChatError>(),
        Some(ChatError::StaleContent)
    ));
    assert!(
        matches!(
            read_content(
                &db,
                &ContentReadRequest {
                    reference: ContentRef::Body(auxiliary),
                    ..request.clone()
                }
            )
            .await
            .unwrap_err()
            .downcast_ref::<ChatError>(),
            Some(ChatError::StaleContent)
        ),
        "withdrawn explicit Current content is retired even when it was not a preview head"
    );
    assert!(
        matches!(
            read_content(
                &db,
                &ContentReadRequest {
                    reference: ContentRef::Body(active_item),
                    ..request.clone()
                }
            )
            .await
            .unwrap_err()
            .downcast_ref::<ChatError>(),
            Some(ChatError::NotFound(_))
        ),
        "withdrawn unsealed Item content must not remain a permanent active reference"
    );
    assert_eq!(
        read_content(
            &db,
            &ContentReadRequest {
                reference: ContentRef::Body(sealed_item),
                ..request.clone()
            }
        )
        .await?
        .bytes
        .as_bytes(),
        b"done",
        "sealed Item content outlives current retirement"
    );
    assert!(matches!(
        current::page(
            &db,
            reference,
            None,
            pl_protocol::ReadDemand {
                max_items: 1,
                max_bytes: 4096,
            },
            &Ok,
        )
        .await
        .unwrap_err()
        .downcast_ref::<ChatError>(),
        Some(ChatError::StaleContent)
    ));
    Ok(())
}

#[tokio::test]
async fn body_chunk_loss_is_not_eof_and_item_missing_is_not_empty() -> Result<()> {
    let (_dir, db) = fixture().await?;
    let missing = ContentReadRequest {
        epoch: TimelineEpoch::new("test")?,
        reference: ContentRef::ItemPayload("missing".into()),
        offset: 0,
        max_bytes: 1,
        generation: None,
    };
    let error = read_content(&db, &missing).await.unwrap_err();
    assert!(matches!(
        error.downcast_ref::<ChatError>(),
        Some(ChatError::NotFound(_))
    ));
    let key = ChatContentKey {
        owner: ChatKey::new("item", "item:1")?,
        key: "body".into(),
    };
    let mut record = item(1, "conversation", b"item");
    record.contents = Arc::new(ChatContents::from([(
        key.clone(),
        Arc::new(ChatContent {
            descriptor: ContentDescriptor {
                key: key.clone(),
                byte_length: 70_000,
                generation: 1,
                media_type: None,
            },
            data: ContentData::Bytes(Arc::from(vec![b'x'; 70_000])),
        }),
    )]));
    append_records(&db, [&record], true).await?;
    db.execute_unprepared("DELETE FROM conversation_content_chunks WHERE byte_offset=65536")
        .await?;
    let lost = ContentReadRequest {
        reference: ContentRef::Body(key),
        offset: 65_535,
        max_bytes: 3,
        ..missing
    };
    assert!(
        read_content(&db, &lost).await.is_err(),
        "missing boundary chunk must not become EOF"
    );
    Ok(())
}

fn legacy(id: &str, seq: u64, kind: &str, data: serde_json::Value) -> Result<String> {
    Ok(serde_json::to_string(&serde_json::json!({
        "itemId":id, "appendSeq":seq, "turnId":"turn:full:id",
        "sourceEffectSeq":4, "sealedAt":15,
        "meta":serde_json::to_vec(&serde_json::json!({
            "id":id,"threadId":"thread","turnId":"turn:full:id",
            "descriptor":{"kind":kind,"data":data}
        }))?,
        "fields":[{"identity":{"kind":"host","value":"tool.result"},"text":"opaque 🦀"}]
    }))?)
}

#[test]
fn published_field_identities_use_the_normal_codec_body_keys() -> Result<()> {
    use crate::studio::runtime::chat_item::BodyKey;
    use pl_core::chat::PresentationPart;
    let fields = [
        (serde_json::json!({"kind":"body"}), BodyKey::Body),
        (
            serde_json::json!({"kind":"outputText","value":2}),
            BodyKey::Part(PresentationPart::OutputText(2)),
        ),
        (
            serde_json::json!({"kind":"reasoningText","value":3}),
            BodyKey::Part(PresentationPart::ReasoningText(3)),
        ),
        (
            serde_json::json!({"kind":"summaryText","value":4}),
            BodyKey::Part(PresentationPart::SummaryText(4)),
        ),
        (
            serde_json::json!({"kind":"host","value":"tool.result"}),
            BodyKey::host("tool.result"),
        ),
    ];
    let mut stored: serde_json::Value = serde_json::from_str(&legacy(
        "keys",
        1,
        "tool",
        serde_json::json!({"unknown":"preserved"}),
    )?)?;
    stored["fields"] = serde_json::Value::Array(fields.iter().enumerate().map(|(position, (identity, _))|
        serde_json::json!({"identity":identity,"text":format!("body-{position} 🦀")})
    ).collect());
    let original = serde_json::to_string(&stored)?;
    let item = migration::convert(
        migration::LegacyCompletion {
            id: "keys",
            seq: 1,
            kind: "tool",
            turn: Some("turn:full:id"),
            source: Some(4),
            sealed_at: Some(15),
            original: &original,
        },
        "thread",
        "database",
    )?;
    let payload: serde_json::Value = serde_json::from_slice(&item.payload)?;
    let actual = payload["bodies"]
        .as_array()
        .unwrap()
        .iter()
        .take(fields.len())
        .map(|body| body["key"].as_str().unwrap().to_owned())
        .collect::<Vec<_>>();
    assert_eq!(
        actual,
        fields
            .iter()
            .map(|(_, key)| key.as_key())
            .collect::<Vec<_>>()
    );
    for (position, (_, key)) in fields.iter().enumerate() {
        let content = item
            .contents
            .values()
            .find(|content| content.descriptor.key.key == key.as_key())
            .unwrap();
        let expected = format!("body-{position} 🦀");
        assert_eq!(
            content.data.range(0, expected.len())?.as_bytes(),
            expected.as_bytes()
        );
    }
    Ok(())
}

#[tokio::test]
async fn unknown_tool_descriptor_and_public_bytes_survive_without_current_decoder() -> Result<()> {
    let source = legacy(
        "old",
        1,
        "tool",
        serde_json::json!({
            "invocation":{"name":"unknown.old.tool","arguments":{"future":"unchanged"}},
            "state":{"kind":"obsolete","value":"do not interpret"}
        }),
    )?;
    let item = migration::convert(
        migration::LegacyCompletion {
            id: "old",
            seq: 1,
            kind: "tool",
            turn: Some("turn:full:id"),
            source: Some(4),
            sealed_at: Some(15),
            original: &source,
        },
        "thread",
        "database",
    )?;
    assert_eq!(item.header.query_class, "activity");
    assert_eq!(
        item.header.parent_id,
        Some(ChatKey::new("turn", "turn:full:id")?)
    );
    let payload: serde_json::Value = serde_json::from_slice(&item.payload)?;
    assert_eq!(payload["data"]["state"]["kind"], "obsolete");
    assert!(payload["data"].get("presentationContract").is_none());
    assert_eq!(
        item.contents
            .values()
            .find(|content| content.descriptor.key.key == "tool.result")
            .unwrap()
            .data
            .range(0, 100)?
            .as_bytes(),
        "opaque 🦀".as_bytes()
    );
    let mut corrupt: serde_json::Value = serde_json::from_str(&source)?;
    corrupt["meta"] = serde_json::json!([255, 0, 254]);
    let original = serde_json::to_string(&corrupt)?;
    let unsupported = migration::convert(
        migration::LegacyCompletion {
            id: "old",
            seq: 1,
            kind: "tool",
            turn: Some("turn:full:id"),
            source: Some(4),
            sealed_at: Some(15),
            original: &original,
        },
        "thread",
        "database",
    )?;
    assert_eq!(
        unsupported
            .contents
            .values()
            .next()
            .unwrap()
            .data
            .range(0, original.len())?
            .as_bytes(),
        original.as_bytes()
    );
    assert!(
        migration::convert(
            migration::LegacyCompletion {
                id: "wrong",
                seq: 1,
                kind: "tool",
                turn: Some("turn:full:id"),
                source: Some(4),
                sealed_at: Some(15),
                original: &source,
            },
            "thread",
            "database"
        )
        .is_err()
    );
    Ok(())
}

#[tokio::test]
async fn frozen_current_cannot_cross_effect_and_rolls_back_with_its_transaction() -> Result<()> {
    let (_dir, db) = fixture().await?;
    let mut projection =
        pl_protocol::CurrentProjection::empty(1, pl_protocol::ThreadStatus::Running);
    projection.interactions = Some(pl_protocol::CurrentCollectionRef {
        database_id: "database".into(),
        collection: "interactions".into(),
        revision: 1,
    });
    let source = pl_protocol::ChatSourceId::ForegroundTurn {
        turn_id: "actual-turn".into(),
    };
    let source_state = pl_protocol::ChatSourceState {
        source: source.clone(),
        lifecycle: pl_protocol::ChatSourceLifecycle::Active,
        started: Some(pl_protocol::ChatFactPosition {
            effect_seq: 1,
            suborder: 2,
        }),
        ended: None,
    };
    let prepared = current::PreparedCurrent {
        source_changes: Arc::from([source_state.clone()]),
        projection,
        changes: Arc::from([current::CurrentEntryChange::Put(
            current::CurrentEntryWrite {
                collection: "interactions".into(),
                position: 19,
                entry_id: "one".into(),
                payload: Arc::from(b"first".as_slice()),
            },
        )]),
        contents: Arc::from([]),
    };
    let tx = db.begin().await?;
    assert!(current::apply(&tx, 2, &prepared).await.is_err());
    append_records(
        &tx,
        [&item(1, "conversation", b"same-effect completion")],
        true,
    )
    .await?;
    current::apply(&tx, 1, &prepared).await?;
    assert_eq!(
        sources::read(&tx, std::slice::from_ref(&source), 1).await?,
        [source_state]
    );
    assert!(
        current::read(&tx).await.is_err(),
        "current cannot exceed watermark"
    );
    tx.execute_unprepared("UPDATE history_meta SET applied_write_seq=1")
        .await?;
    let view = current::read(&tx).await?;
    assert_eq!(view.source_effect_seq, 1);
    assert!(!view.execution_present);
    current::verify(&tx, &prepared).await?;
    let mut changed = prepared.clone();
    changed.changes = Arc::from([current::CurrentEntryChange::Put(
        current::CurrentEntryWrite {
            collection: "interactions".into(),
            position: 19,
            entry_id: "one".into(),
            payload: Arc::from(b"other".as_slice()),
        },
    )]);
    assert!(
        matches!(
            current::verify(&tx, &changed)
                .await
                .unwrap_err()
                .downcast_ref::<ChatError>(),
            Some(ChatError::Conflict(_))
        ),
        "same-length retry payload changes must not be acknowledged"
    );
    assert!(
        current::validate_collection(
            &view,
            &pl_protocol::CurrentCollectionRef {
                database_id: "database".into(),
                collection: "missing".into(),
                revision: 1,
            }
        )
        .is_err()
    );
    current::apply(
        &tx,
        1,
        &current::PreparedCurrent {
            source_changes: std::sync::Arc::from([]),
            projection: prepared.projection.clone(),
            changes: Arc::from([
                current::CurrentEntryChange::Remove {
                    collection: "interactions".into(),
                    entry_id: "one".into(),
                },
                current::CurrentEntryChange::Clear {
                    collection: "interactions".into(),
                },
            ]),
            contents: Arc::from([]),
        },
    )
    .await?;
    tx.rollback().await?;
    assert_eq!(latest_append_seq(&db).await?, 0);
    assert!(matches!(
        sources::read(&db, &[source], 1).await?[0].lifecycle,
        pl_protocol::ChatSourceLifecycle::Unknown
    ));
    assert!(
        current::read(&db).await.is_err(),
        "rolled-back current is absent, not checkpoint fallback"
    );
    Ok(())
}

/// Component-level proof of the pinned framework's transaction contract using the actual DDL and
/// backfill implementation. The final production migration additionally owns checkpoint/current
/// seeding and the existing format/identity preflight.
struct TransactionProbe;
impl sea_orm_migration::MigrationName for TransactionProbe {
    fn name(&self) -> &str {
        "storage_243_transaction_probe"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl sea_orm_migration::MigrationTrait for TransactionProbe {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &sea_orm_migration::SchemaManager) -> Result<(), sea_orm::DbErr> {
        let db = manager.get_connection();
        db.execute_unprepared(migration::CREATE_SCHEMA).await?;
        migration::backfill(db, "thread")
            .await
            .map_err(|error| sea_orm::DbErr::Migration(format!("{error:#}")))?;
        db.execute_unprepared("UPDATE history_meta SET schema_version=12")
            .await?;
        Ok(())
    }
}
struct ProbeMigrator;
impl sea_orm_migration::MigratorTraitSelf for ProbeMigrator {
    fn migrations(&self) -> Vec<Box<dyn sea_orm_migration::MigrationTrait>> {
        vec![Box::new(TransactionProbe)]
    }
}

#[tokio::test]
async fn actual_backfill_ddl_marker_and_seaorm_receipt_rollback_then_retry() -> Result<()> {
    use sea_orm_migration::MigratorTraitSelf;
    let dir = tempfile::tempdir()?;
    let mut options = sea_orm::ConnectOptions::new(format!(
        "sqlite://{}?mode=rwc",
        dir.path().join("history.sqlite").display()
    ));
    options
        .max_connections(1)
        .min_connections(1)
        .sqlx_logging(false);
    let db = Database::connect(options).await?;
    db.execute_unprepared(
        "CREATE TABLE history_meta(id INTEGER PRIMARY KEY,schema_version INTEGER,database_id TEXT);
         INSERT INTO history_meta VALUES(1,11,'database');
         CREATE TABLE timeline_records(append_seq INTEGER PRIMARY KEY,record_id TEXT UNIQUE,
             turn_id TEXT,source_effect_seq INTEGER,sealed_at INTEGER,kind TEXT,payload TEXT);",
    )
    .await?;
    let first = legacy("one", 1, "tool", serde_json::json!({"old":"opaque"}))?;
    let second = legacy("two", 2, "text", serde_json::json!({"future":"retained"}))?;
    for (seq, id, kind, payload) in [
        (1, "one", "tool", first.as_str()),
        (2, "wrong-index-id", "text", second.as_str()),
    ] {
        db.execute_raw(statement(
            "INSERT INTO timeline_records VALUES(?,?,?,4,15,?,?)",
            vec![
                seq.into(),
                id.into(),
                "turn:full:id".into(),
                kind.into(),
                payload.into(),
            ],
        ))
        .await?;
    }
    assert!(ProbeMigrator.up(&db, None).await.is_err());
    assert!(
        db.query_one_raw(statement(
            "SELECT 1 FROM sqlite_schema WHERE name='conversation_items'",
            vec![],
        ))
        .await?
        .is_none(),
        "DDL must roll back on the real migration transaction"
    );
    assert_eq!(
        db.query_one_raw(statement("SELECT schema_version FROM history_meta", vec![]))
            .await?
            .unwrap()
            .try_get::<i64>("", "schema_version")?,
        11
    );
    assert!(
        db.query_one_raw(statement(
            "SELECT 1 FROM seaql_migrations WHERE version='storage_243_transaction_probe'",
            vec![],
        ))
        .await?
        .is_none()
    );
    assert_eq!(
        db.query_one_raw(statement(
            "SELECT payload FROM timeline_records WHERE append_seq=1",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get::<String>("", "payload")?,
        first
    );
    db.execute_unprepared("UPDATE timeline_records SET record_id='two' WHERE append_seq=2")
        .await?;
    ProbeMigrator.up(&db, None).await?;
    assert_eq!(latest_append_seq(&db).await?, 2);
    assert!(
        db.query_one_raw(statement(
            "SELECT 1 FROM seaql_migrations WHERE version='storage_243_transaction_probe'",
            vec![],
        ))
        .await?
        .is_some()
    );
    ProbeMigrator.up(&db, None).await?;
    assert_eq!(latest_append_seq(&db).await?, 2);
    Ok(())
}

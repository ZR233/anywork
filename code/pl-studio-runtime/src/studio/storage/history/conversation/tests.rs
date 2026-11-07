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

pub(super) async fn fixture() -> Result<(tempfile::TempDir, DatabaseConnection)> {
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
        content_present: None,
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
async fn cold_scope_budget_fits_exact_item_and_child_envelopes_without_decoding_payload()
-> Result<()> {
    use pl_protocol::{ChatBatch, ChatEntry, ChatPlacement, ChatScope};
    // Budget the complete wire envelope, not a synthetic per-row byte constant.
    // Match the reader's conservative source annotation and JSON byte-array bound;
    // the opaque fixture payload must never be decoded to make this decision.
    struct EnvelopeBudget {
        database_id: String,
        empty: ChatBatch,
    }
    impl EnvelopeBudget {
        fn entry(&self, header: &ChatItemHeader, mode: PayloadMode) -> Result<ChatEntry> {
            let mut atom: pl_protocol::ChatAtom = serde_json::from_slice(&header.metadata)?;
            atom.completion_seq = Some(header.append_seq);
            atom.payload = Some(match mode {
                PayloadMode::Inline => pl_protocol::PayloadData::Inline { bytes: Vec::new() },
                PayloadMode::Deferred => pl_protocol::PayloadData::Deferred {
                    reference: pl_protocol::ContentRef {
                        database_id: self.database_id.clone(),
                        target: pl_protocol::ContentTarget::ItemPayload {
                            item_id: header.item_id.clone(),
                        },
                    },
                    byte_length: header.byte_length,
                },
            });
            Ok(ChatEntry::Atom(Box::new(atom)))
        }
    }
    impl ChatBudget for EnvelopeBudget {
        fn fixed_bytes(&self) -> usize {
            serde_json::to_vec(&self.empty).unwrap().len()
        }
        fn item_bytes(&self, header: &ChatItemHeader, mode: PayloadMode) -> usize {
            let base = timeline::entry_bytes(&self.entry(header, mode).unwrap()).unwrap();
            if mode == PayloadMode::Inline {
                base + usize::try_from(header.byte_length).unwrap() * 4
            } else {
                base
            }
        }
        fn manifest_bytes(&self, _: &ContentDescriptor) -> usize {
            unreachable!("this test does not read a content manifest")
        }
    }
    let dir = tempfile::tempdir()?;
    let store =
        super::super::HistoryStore::open(&dir.path().join("history.sqlite"), "cold-budget").await?;
    store.prepare_write().await?;
    let parent = ChatKey::new("turn", "actual-parent")?;
    let mut records = Vec::new();
    for seq in 1..=3 {
        let mut record = item(seq, "conversation", &[255; 2048]);
        record.header.metadata = metadata(&record.header.item_id);
        if seq == 2 {
            record.header.parent_id = Some(parent.clone());
        }
        records.push(Arc::new(record));
    }
    let current = super::super::test_current(1);
    store
        .commit_effect(
            1,
            super::super::EffectCommit {
                items: &[],
                completions: &records,
                current: &current,
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
        .await?;
    // The synthetic fixture represents frozen legacy facts, prepared once at
    // their formal normalization boundary, not a second normal Main algorithm.
    let connection = store.writer().await?;
    let tx = connection.db.begin().await?;
    for record in &records {
        let mut atom: pl_protocol::ChatAtom = serde_json::from_slice(&record.header.metadata)?;
        atom.completion_seq = Some(record.header.append_seq);
        tx.execute_raw(statement(
            "INSERT INTO conversation_atom_facts(effect_seq,suborder,atom_id,phase,fact_order,metadata) VALUES(1,?,?,'terminal',?,?)",
            vec![integer(record.header.append_seq)?.into(),atom.id.clone().into(),
                integer(record.header.append_seq)?.into(),serde_json::to_vec(&atom)?.into()],
        )).await?;
    }
    let generation = uuid::Uuid::new_v4().to_string();
    timeline::complete::rebuild(&tx, &connection.database_id, generation.clone(), 1).await?;
    tx.commit().await?;
    // The synthetic legacy fixture is prepared before admitting any consumer.
    // There is no normal read-triggered rebuild or live maintenance entry.
    store.state.timeline_generation.send_replace(generation);
    let budget = EnvelopeBudget {
        database_id: connection.database_id.clone(),
        empty: ChatBatch {
            placement: ChatPlacement::Prepend,
            entries: Vec::new(),
            before: Some("cold-budget-continuation".into()),
            current: None,
        },
    };
    let cold = store
        .cold_timeline(&ChatScope::Main, ReadDemand::new(1, 256 * 1024), &budget)
        .await?
        .unwrap();
    let page = cold.timeline.context("derived page")?;
    assert!(cold.page.items.is_empty(), "Main selected atomic records");
    let [pl_protocol::ChatEntry::Item(latest)] = page.entries.as_slice() else {
        panic!("Main returned Atom");
    };
    assert_eq!(latest.position, Some(2));
    assert_eq!(latest.content_item_id.as_deref(), Some("item:3"));
    assert!(matches!(
        latest.payload,
        Some(pl_protocol::PayloadData::Deferred { .. })
    ));
    let minimum = budget.fixed_bytes() + serde_json::to_vec(&cold.current)?.len() - b"null".len()
        + timeline::entry_bytes(&page.entries[0])?;
    let exact = store
        .cold_timeline(&ChatScope::Main, ReadDemand::new(1, minimum), &budget)
        .await?
        .unwrap();
    assert_eq!(exact.timeline.unwrap().entries, page.entries);
    let mut main_envelope = budget.empty.clone();
    main_envelope.entries = page.entries.clone();
    main_envelope.current = Some(cold.current.clone());
    assert!(serde_json::to_vec(&main_envelope)?.len() <= minimum);
    assert!(
        store
            .cold_timeline(&ChatScope::Main, ReadDemand::new(1, minimum - 1), &budget)
            .await
            .is_err()
    );
    let child_minimum =
        budget.fixed_bytes() + budget.item_bytes(&records[1].header, PayloadMode::Deferred);
    let query = ChatQuery::new("conversation", Some(parent));
    let child = store
        .cold_conversation(query.clone(), ReadDemand::new(1, child_minimum), &budget)
        .await?
        .unwrap();
    assert_eq!(child.page.items.len(), 1);
    assert_eq!(child.page.items[0].header, records[1].header);
    assert!(matches!(
        child.page.items[0].payload,
        PayloadData::Deferred { .. }
    ));
    let mut child_envelope = budget.empty.clone();
    child_envelope.entries =
        vec![budget.entry(&child.page.items[0].header, PayloadMode::Deferred)?];
    assert!(serde_json::to_vec(&child_envelope)?.len() <= child_minimum);
    assert!(
        !child.page.exhausted,
        "a full scoped page conservatively continues without an existence probe"
    );
    let short = store
        .cold_conversation(query.clone(), ReadDemand::new(2, child_minimum), &budget)
        .await?
        .unwrap();
    assert_eq!(short.page.items, child.page.items);
    assert!(short.page.exhausted, "a short scoped page proves EOF");
    let end = super::page(
        &connection.db,
        &ChatHistoryRequest {
            query: Some(query.clone()),
            after: 0,
            before: Some(records[1].header.append_seq),
            ceiling: records[2].header.append_seq,
            demand: ReadDemand::new(1, child_minimum),
        },
        &budget,
        false,
    )
    .await?;
    assert!(end.items.is_empty());
    assert!(end.exhausted, "an empty scoped continuation proves EOF");
    assert!(
        store
            .cold_conversation(query, ReadDemand::new(1, child_minimum - 1), &budget)
            .await
            .is_err()
    );
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

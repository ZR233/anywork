use super::super::super::{AccountingCommit, CheckpointEffect, EffectCommit, HistoryStore};
use super::*;
use sea_orm_migration::MigratorTraitSelf;

const THREAD: &str = "demand-migration";

struct Published11;
impl MigratorTraitSelf for Published11 {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        Migrator {
            thread_id: THREAD.into(),
            execution_identity: None,
            bot_root: None,
        }
        .migrations()
        .into_iter()
        .filter(|step| {
            !matches!(
                step.name(),
                BACKGROUND_RESULTS | MEMBER_READ_METADATA | SOURCE_CLASSIFICATION
            )
        })
        .filter(|step| {
            !matches!(
                step.name(),
                DEMAND_CONVERSATION | MODEL_ROUTE_HEAD | ATOM_METADATA | TIMELINE_ITEMS
            )
        })
        .collect()
    }
}

/// Exercise the published 11→12 transition without silently replacing its target with 13.
struct Published12;
impl MigratorTraitSelf for Published12 {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        Migrator {
            thread_id: THREAD.into(),
            execution_identity: None,
            bot_root: None,
        }
        .migrations()
        .into_iter()
        .filter(|step| {
            !matches!(
                step.name(),
                BACKGROUND_RESULTS | MEMBER_READ_METADATA | SOURCE_CLASSIFICATION
            )
        })
        .filter(|step| {
            !matches!(
                step.name(),
                MODEL_ROUTE_HEAD | ATOM_METADATA | TIMELINE_ITEMS
            )
        })
        .collect()
    }
}

async fn prepare_published12(db: &DatabaseConnection) -> Result<()> {
    preflight(db, THREAD).await?;
    let steps = Published12
        .get_pending_migrations_read_only(db)
        .await?
        .iter()
        .take_while(|step| !is_lifecycle_migration(step.name()))
        .count();
    Published12.up(db, Some(u32::try_from(steps)?)).await?;
    Ok(())
}

async fn source() -> Result<(tempfile::TempDir, DatabaseConnection)> {
    let dir = tempfile::tempdir()?;
    let db = super::super::super::connect(
        &dir.path().join("history.sqlite"),
        crate::studio::paths::SqliteFileMode::Create,
    )
    .await?;
    let count = Published11
        .migrations()
        .iter()
        .take_while(|step| !is_lifecycle_migration(step.name()))
        .count();
    Published11.up(&db, Some(u32::try_from(count)?)).await?;
    assert_eq!(version(&db).await?, 11);
    Ok((dir, db))
}

/// Explicit observation, not a machine-sensitive timing gate in the normal suite.
/// Fixture setup and the data-preservation audit are outside the measured interval.
#[tokio::test]
#[ignore = "explicit nonempty migration cost observation"]
async fn nonempty_schema11_migration_cost_is_separate_from_current_reads() -> Result<()> {
    use sea_orm::TransactionTrait as _;
    for count in [100_u64, 20_000] {
        let (_dir, db) = source().await?;
        let tx = db.begin().await?;
        for seq in 1..=count {
            let id = format!("old-{seq}");
            let kind = if seq % 2 == 0 { "tool" } else { "text" };
            tx.execute_raw(statement(
                "INSERT INTO timeline_records(append_seq,record_id,turn_id,kind,payload)
                 VALUES(?,?,'a:b',?,?)",
                vec![
                    integer(seq)?.into(),
                    id.clone().into(),
                    kind.into(),
                    record(&id, seq, kind)?.into(),
                ],
            ))
            .await?;
        }
        tx.commit().await?;
        assert_eq!(version(&db).await?, 11);
        let started = std::time::Instant::now();
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        let migration_us = started.elapsed().as_micros();
        assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
        assert_eq!(conversation::latest_append_seq(&db).await?, count);
        let mismatch: i64 = db
            .query_one_raw(statement(
                "SELECT count(*) AS n FROM timeline_records old
                 LEFT JOIN conversation_items new ON new.seq=old.append_seq
                 WHERE new.item_id IS NULL OR new.item_id<>old.record_id
                    OR new.query_class<>CASE WHEN old.kind='tool' THEN 'activity' ELSE 'conversation' END",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "n")?;
        assert_eq!(mismatch, 0);
        for seq in [1, count] {
            let item = conversation::read_item(&db, &format!("old-{seq}"))
                .await?
                .unwrap();
            let payload: serde_json::Value = serde_json::from_slice(&item.payload)?;
            assert_eq!(payload["data"]["oldUnknown"]["opaque"], "原文 🦀");
            let content = item
                .contents
                .values()
                .find(|content| content.descriptor.key.key == "tool.result")
                .unwrap();
            assert_eq!(
                content
                    .data
                    .range(0, content.descriptor.byte_length as usize)?
                    .as_bytes(),
                "公开原文 🦀".as_bytes()
            );
        }
        println!(
            "{}",
            serde_json::json!({
                "observation": "schema11_to_current",
                "sourceRows": count,
                "sourceSchema": 11,
                "targetSchema": HISTORY_SCHEMA_VERSION,
                "migrationMicros": migration_us,
                "identityOrScopeMismatches": mismatch,
            })
        );
        db.close().await?;
    }
    Ok(())
}

fn record(id: &str, seq: u64, kind: &str) -> Result<String> {
    Ok(serde_json::to_string(&serde_json::json!({
        "itemId":id,"appendSeq":seq,"turnId":"a:b","sourceEffectSeq":null,"sealedAt":null,
        "meta":serde_json::to_vec(&serde_json::json!({
            "id":id,"threadId":THREAD,"turnId":"a:b",
            "descriptor":{"kind":kind,"data":{"oldUnknown":{"opaque":"原文 🦀"}}}
        }))?,
        "fields":[{"identity":{"kind":"host","value":"tool.result"},"text":"公开原文 🦀"}]
    }))?)
}

/// Inspect the published schema-12 representation without invoking a current-format reader.
async fn published_item(db: &DatabaseConnection, id: &str) -> Result<pl_core::chat::ChatItem> {
    let row = db.query_one_raw(statement(
        "SELECT seq,item_id,query_class,parent_id,payload FROM conversation_items WHERE item_id=?",
        vec![id.into()],
    )).await?.context("published item missing")?;
    let mut draft = pl_core::chat::ChatDraft::new(
        row.try_get::<String>("", "item_id")?,
        row.try_get::<String>("", "query_class")?,
        std::sync::Arc::from(row.try_get::<Vec<u8>>("", "payload")?),
    );
    draft.parent_id = row
        .try_get::<Option<String>>("", "parent_id")?
        .map(pl_core::chat::ChatKey::from_encoded)
        .transpose()?;
    draft.contents = std::sync::Arc::new(conversation::read_contents(db, id).await?);
    Ok(pl_core::chat::ChatItem::complete(
        draft,
        u64::try_from(row.try_get::<i64>("", "seq")?)?,
    ))
}

async fn insert(
    db: &DatabaseConnection,
    id: &str,
    seq: u64,
    kind: &str,
    payload: &str,
) -> Result<()> {
    db.execute_raw(statement(
        "INSERT INTO timeline_records(append_seq,record_id,turn_id,source_effect_seq,sealed_at,kind,payload)
         VALUES(?,?,'a:b',NULL,NULL,?,?)",
        vec![integer(seq)?.into(), id.into(), kind.into(), payload.into()],
    )).await?;
    Ok(())
}

#[tokio::test]
async fn formal_schema12_preserves_nonempty_unknown_records_and_identity() -> Result<()> {
    let (_dir, db) = source().await?;
    let original = record("old-tool", 1, "tool")?;
    insert(&db, "old-tool", 1, "tool", &original).await?;
    let mut malformed: serde_json::Value = serde_json::from_str(&record("bad-meta", 2, "tool")?)?;
    malformed["meta"] = serde_json::json!([255, 254, 0]);
    let malformed = serde_json::to_string(&malformed)?;
    insert(&db, "bad-meta", 2, "tool", &malformed).await?;
    insert(&db, "neighbor", 3, "text", &record("neighbor", 3, "text")?).await?;
    let before: String = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get("", "database_id")?;
    prepare_published12(&db).await?;
    assert_eq!(version(&db).await?, 12);
    let item = published_item(&db, "old-tool").await?;
    assert_eq!(item.header.append_seq, 1);
    assert_eq!(item.header.query_class, "activity");
    assert_eq!(
        item.header.parent_id,
        Some(pl_core::chat::ChatKey::new("turn", "a:b")?)
    );
    let payload: serde_json::Value = serde_json::from_slice(&item.payload)?;
    assert_eq!(payload["data"]["oldUnknown"]["opaque"], "原文 🦀");
    assert!(payload["data"].get("presentationContract").is_none());
    assert_eq!(conversation::latest_append_seq(&db).await?, 3);
    let unsupported = published_item(&db, "bad-meta").await?;
    let content = unsupported.contents.values().next().unwrap();
    assert_eq!(content.descriptor.key.key, "legacy.record");
    assert_eq!(
        content.data.range(0, malformed.len())?.as_bytes(),
        malformed.as_bytes()
    );
    assert_eq!(
        db.query_one_raw(statement(
            "SELECT payload FROM timeline_records WHERE record_id='old-tool'",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get::<String>("", "payload")?,
        original
    );
    assert_eq!(
        db.query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get::<String>("", "database_id")?,
        before
    );
    assert!(!conversation::current::read(&db).await?.execution_present);
    prepare_published12(&db).await?;
    assert_eq!(conversation::latest_append_seq(&db).await?, 3);
    Ok(())
}

#[tokio::test]
async fn formal_migration_rolls_back_all_outputs_and_bookkeeping_then_retries() -> Result<()> {
    let (_dir, db) = source().await?;
    let first = record("one", 1, "text")?;
    insert(&db, "one", 1, "text", &first).await?;
    insert(&db, "wrong-index", 2, "tool", &record("two", 2, "tool")?).await?;
    assert!(prepare_published12(&db).await.is_err());
    assert_eq!(version(&db).await?, 11);
    for table in [
        "conversation_items",
        "conversation_contents",
        "conversation_content_chunks",
        "conversation_view_state",
        "conversation_view_entries",
    ] {
        assert!(!SchemaManager::new(&db).has_table(table).await?);
    }
    assert!(
        db.query_one_raw(statement(
            "SELECT 1 FROM seaql_migrations WHERE version=?",
            vec![DEMAND_CONVERSATION.into()],
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
    prepare_published12(&db).await?;
    assert_eq!(version(&db).await?, 12);
    assert_eq!(conversation::latest_append_seq(&db).await?, 2);
    Ok(())
}

#[tokio::test]
async fn formal_migration_rejects_malformed_nullable_provenance_and_retries() -> Result<()> {
    use serde_json::{Value as Json, json};

    let cases = [
        ("sourceEffectSeq", json!("damaged")),
        ("sourceEffectSeq", json!(-1)),
        ("sourceEffectSeq", json!(1.5)),
        ("sourceEffectSeq", json!(u64::MAX)),
        (
            "sourceEffectSeq",
            serde_json::from_str::<Json>("18446744073709551616")?,
        ),
        ("turnId", json!(123)),
        ("turnId", json!(true)),
        ("sealedAt", json!("damaged")),
        ("sealedAt", json!(false)),
        ("sealedAt", json!(i64::MAX as u64 + 1)),
        (
            "sealedAt",
            serde_json::from_str::<Json>("-9223372036854775809")?,
        ),
        ("sealedAt", json!(1.5)),
    ];
    for (index, (field, value)) in cases.iter().enumerate() {
        let (_dir, db) = source().await?;
        let first = record("neighbor", 1, "text")?;
        insert(&db, "neighbor", 1, "text", &first).await?;
        let mut container = json!({
            "itemId":"damaged","appendSeq":2,
            "turnId":null,"sourceEffectSeq":null,"sealedAt":null,
            "meta":serde_json::to_vec(&json!({
                "id":"damaged","threadId":THREAD,
                "descriptor":{"kind":"tool","data":{"unknown":"保留原文 🦀"}}
            }))?,
            "fields":[{"identity":{"kind":"host","value":"tool.result"},"text":"公开原文 🦀"}]
        });
        container[*field] = value.clone();
        let malformed = serde_json::to_string(&container)?;
        db.execute_raw(statement(
            "INSERT INTO timeline_records(append_seq,record_id,turn_id,source_effect_seq,sealed_at,kind,payload)
             VALUES(2,'damaged',NULL,NULL,NULL,'tool',?)",
            vec![malformed.clone().into()],
        )).await?;
        let applied = db
            .query_all_raw(statement(
                "SELECT version FROM seaql_migrations ORDER BY version",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| row.try_get::<String>("", "version"))
            .collect::<std::result::Result<Vec<_>, _>>()?;

        let error = prepare_published12(&db)
            .await
            .expect_err("malformed optional provenance must not compare equal to a NULL index");
        let diagnostic = format!("{error:#}");
        assert!(
            diagnostic.contains("provenance") || diagnostic.contains("sourceEffectSeq"),
            "{field}={value}: {diagnostic}"
        );
        assert_eq!(version(&db).await?, 11);
        for table in [
            "conversation_items",
            "conversation_contents",
            "conversation_content_chunks",
            "conversation_view_state",
            "conversation_view_entries",
        ] {
            assert!(
                !SchemaManager::new(&db).has_table(table).await?,
                "{field}={value}: {table}"
            );
        }
        let after = db
            .query_all_raw(statement(
                "SELECT version FROM seaql_migrations ORDER BY version",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| row.try_get::<String>("", "version"))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        assert_eq!(
            after, applied,
            "failed migration must publish no SeaORM record"
        );
        assert!(!after.iter().any(|name| name == DEMAND_CONVERSATION));
        let original = db
            .query_all_raw(statement(
                "SELECT payload FROM timeline_records ORDER BY append_seq",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| row.try_get::<String>("", "payload"))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        assert_eq!(
            original,
            [first, malformed],
            "all source bytes must survive rollback"
        );

        // Repair only the offending header in this original database. Missing and explicit NULL
        // are both published optional-field representations and must remain legal.
        if index % 2 == 0 {
            container.as_object_mut().unwrap().remove(*field);
        } else {
            container[*field] = Json::Null;
        }
        let corrected = serde_json::to_string(&container)?;
        db.execute_raw(statement(
            "UPDATE timeline_records SET payload=? WHERE record_id='damaged'",
            vec![corrected.clone().into()],
        ))
        .await?;
        prepare_published12(&db).await?;
        assert_eq!(version(&db).await?, 12);
        assert_eq!(conversation::latest_append_seq(&db).await?, 2);
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM seaql_migrations WHERE version=?",
                vec![DEMAND_CONVERSATION.into()],
            ))
            .await?
            .is_some()
        );
        let migrated = published_item(&db, "damaged").await?;
        let retained = migrated
            .contents
            .values()
            .find(|content| content.descriptor.key.key == "legacy.record")
            .context("original unknown tool container must remain declared content")?;
        assert_eq!(
            retained.data.range(0, corrected.len())?.as_bytes(),
            corrected.as_bytes()
        );
    }
    eprintln!(
        "formal nullable provenance: {} malformed NULL-index cases rolled back and retried; missing/null repairs both accepted",
        cases.len()
    );
    Ok(())
}

#[tokio::test]
async fn formal_current_entries_validate_one_ordered_composite_unique_constraint() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let store = HistoryStore::open(&dir.path().join("history.sqlite"), THREAD).await?;
    store.prepare_write().await?;
    let db = &store.writer().await?.db;
    assert_eq!(
        version(db).await?,
        HISTORY_SCHEMA_VERSION,
        "the real new-store migration must finish"
    );
    for (collection, position, id) in [("a", 1i64, "same"), ("a", 2, "other"), ("b", 1, "same")] {
        db.execute_raw(statement(
            "INSERT INTO conversation_view_entries(collection,position,entry_id,payload) VALUES(?,?,?,?)",
            vec![collection.into(), position.into(), id.into(), b"{}".to_vec().into()],
        )).await?;
    }
    assert!(db.execute_raw(statement(
        "INSERT INTO conversation_view_entries(collection,position,entry_id,payload) VALUES('a',3,'same',?)",
        vec![b"{}".to_vec().into()],
    )).await.is_err(), "only the same collection + entry identity conflicts");
    validate_tables(db).await?;

    let valid_columns = "collection TEXT NOT NULL,position INTEGER NOT NULL,entry_id TEXT NOT NULL,payload BLOB NOT NULL,PRIMARY KEY(collection,position)";
    for (name, ddl) in [
        ("absent", format!("CREATE TABLE conversation_view_entries({valid_columns}) WITHOUT ROWID")),
        ("reversed", format!("CREATE TABLE conversation_view_entries({valid_columns},UNIQUE(entry_id,collection)) WITHOUT ROWID")),
        ("descending", format!("CREATE TABLE conversation_view_entries({valid_columns},UNIQUE(collection DESC,entry_id)) WITHOUT ROWID")),
        ("nocase", format!("CREATE TABLE conversation_view_entries({valid_columns},UNIQUE(collection,entry_id COLLATE NOCASE)) WITHOUT ROWID")),
        ("nullable", "CREATE TABLE conversation_view_entries(collection TEXT NOT NULL,position INTEGER NOT NULL,entry_id TEXT,payload BLOB NOT NULL,PRIMARY KEY(collection,position),UNIQUE(collection,entry_id)) WITHOUT ROWID".into()),
        ("singles", "CREATE TABLE conversation_view_entries(collection TEXT NOT NULL UNIQUE,position INTEGER NOT NULL,entry_id TEXT NOT NULL UNIQUE,payload BLOB NOT NULL,PRIMARY KEY(collection,position)) WITHOUT ROWID".into()),
        ("partial", format!("CREATE TABLE conversation_view_entries({valid_columns}) WITHOUT ROWID; CREATE UNIQUE INDEX damaged_entry_unique ON conversation_view_entries(collection,entry_id) WHERE position>=0")),
        ("expression", format!("CREATE TABLE conversation_view_entries({valid_columns}) WITHOUT ROWID; CREATE UNIQUE INDEX damaged_entry_unique ON conversation_view_entries(collection,lower(entry_id))")),
    ] {
        db.execute_unprepared("DROP TABLE conversation_view_entries").await?;
        db.execute_unprepared(&ddl).await?;
        assert!(validate_tables(db).await.is_err(), "damaged {name} constraint must fail closed");
    }
    Ok(())
}

#[tokio::test]
async fn future_schema_is_refused_without_mutating_source() -> Result<()> {
    let (_dir, db) = source().await?;
    db.execute_unprepared("UPDATE history_meta SET schema_version=99")
        .await?;
    assert!(
        prepare(&db, THREAD, Preparation::Schema, None)
            .await
            .is_err()
    );
    assert_eq!(version(&db).await?, 99);
    assert!(
        !SchemaManager::new(&db)
            .has_table("conversation_items")
            .await?
    );
    Ok(())
}

unsafe extern "C" fn deny_quick_check(
    _: *mut std::ffi::c_void,
    action: i32,
    argument: *const std::ffi::c_char,
    _: *const std::ffi::c_char,
    _: *const std::ffi::c_char,
    _: *const std::ffi::c_char,
) -> i32 {
    if action == libsqlite3_sys::SQLITE_PRAGMA && !argument.is_null() {
        // SAFETY: SQLite supplies a live NUL-terminated action argument for this callback.
        // It is inspected synchronously and neither retained nor passed across threads.
        if unsafe { std::ffi::CStr::from_ptr(argument) }
            .to_bytes()
            .eq_ignore_ascii_case(b"quick_check")
        {
            return libsqlite3_sys::SQLITE_DENY;
        }
    }
    libsqlite3_sys::SQLITE_OK
}

#[tokio::test]
async fn current_admission_neither_quick_checks_nor_decodes_recovery_checkpoint() -> Result<()> {
    let (_dir, db) = source().await?;
    prepare(&db, THREAD, Preparation::Schema, None).await?;
    let checkpoint = pl_core::thread::ThreadCheckpoint::capture(
        THREAD.into(),
        0,
        pl_core::thread::ThreadSnapshot::default(),
    );
    checkpoint::write(&db, &checkpoint, None, None).await?;
    db.execute_unprepared(
        "UPDATE session_checkpoint SET payload='{\"schemaVersion\":999}' WHERE id=1",
    )
    .await?;
    {
        let mut connection = db.get_sqlite_connection_pool().acquire().await?;
        let mut handle = connection.lock_handle().await?;
        // SAFETY: the SQLx handle excludes its worker while installing the callback. The callback
        // is a static function, has no borrowed user data, and remains valid until SQLite closes
        // this connection, including error/cancellation paths. It never reenters SQLite.
        let result = unsafe {
            libsqlite3_sys::sqlite3_set_authorizer(
                handle.as_raw_handle().as_ptr(),
                Some(deny_quick_check),
                std::ptr::null_mut(),
            )
        };
        assert_eq!(result, libsqlite3_sys::SQLITE_OK);
    }
    assert!(
        db.query_all_raw(statement("PRAGMA quick_check", vec![]))
            .await
            .is_err()
    );
    super::super::super::validate_existing(&db, THREAD).await?;
    assert!(
        checkpoint::read(&db, THREAD).await.is_err(),
        "explicit recovery still validates the sentinel"
    );
    Ok(())
}

#[tokio::test]
async fn production_batch_commits_context_completions_and_current_as_one_prefix() -> Result<()> {
    use pl_core::{
        context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource},
        thread::{ThreadCheckpoint, ThreadEffectBatch, ThreadSnapshot, journal::ContextChange},
    };
    let dir = tempfile::tempdir()?;
    let store = HistoryStore::open(&dir.path().join("history.sqlite"), THREAD).await?;
    let _writer = store.writer().await?;
    let record = |id: &str| ContextRecord {
        id: id.into(),
        turn_id: None,
        source: ContextSource::Instruction,
        content: vec![ContextContent::Text {
            text: Arc::from(id),
        }],
        tool_calls: vec![],
    };
    let first_record = record("one");
    let second_record = record("two");
    let first_state = ThreadSnapshot {
        commit_sequence: 1,
        context: ContextSnapshot {
            revision: 1,
            records: vec![first_record.clone()].into(),
        },
        ..Default::default()
    };
    let second_state = ThreadSnapshot {
        commit_sequence: 2,
        context: ContextSnapshot {
            revision: 2,
            records: vec![first_record.clone(), second_record.clone()].into(),
        },
        ..Default::default()
    };
    let mut first = ThreadCheckpoint::capture(THREAD.into(), 1, first_state);
    let mut second = ThreadCheckpoint::capture(THREAD.into(), 2, second_state);
    for (checkpoint, revision, model) in [
        (&mut first, 1, "first-model"),
        (&mut second, 2, "second-model"),
    ] {
        checkpoint.state.extensions.insert(
            crate::studio::model_route::MODEL_ROUTE_EXTENSION.into(),
            pl_core::thread::extensions::ExtensionRecord {
                revision,
                payload: crate::studio::model_route::encode(&pl_model::config::ModelRouteConfig {
                    account_id: pl_model::config::AccountId::new("batch-account")?,
                    model_id: model.into(),
                    effort: None,
                })?,
            },
        );
        checkpoint.state.extension_sequence = revision;
    }
    let e1 = ThreadEffectBatch {
        thread_id: THREAD.into(),
        sequence: 1,
        context: Some(ContextChange::Append {
            revision: 1,
            records: vec![first_record].into(),
        }),
        ..Default::default()
    };
    let e2 = ThreadEffectBatch {
        thread_id: THREAD.into(),
        sequence: 2,
        context: Some(ContextChange::Append {
            revision: 2,
            records: vec![second_record].into(),
        }),
        ..Default::default()
    };
    let a1 = crate::studio::thread_projection::PreparedAccounting::prepare(&e1)?;
    let a2 = crate::studio::thread_projection::PreparedAccounting::prepare(&e2)?;
    a1.fold_into(&mut first.state.usage_summary);
    second.state.usage_summary = first.state.usage_summary.clone();
    a2.fold_into(&mut second.state.usage_summary);
    let c1 = super::super::super::test_current(1);
    let c2 = super::super::super::test_current(2);
    let empty = std::collections::BTreeSet::new();
    let completions1 = [Arc::new(pl_core::chat::ChatItem::complete(
        pl_core::chat::ChatDraft::new("first", "conversation", Arc::from(b"{}".as_slice())),
        1,
    ))];
    let completions2 = [Arc::new(pl_core::chat::ChatItem::complete(
        pl_core::chat::ChatDraft::new("second", "conversation", Arc::from(b"{}".as_slice())),
        2,
    ))];
    fn history<'a>(
        current: &'a PreparedCurrent,
        completions: &'a [Arc<pl_core::chat::ChatItem>],
        empty: &'a std::collections::BTreeSet<String>,
    ) -> EffectCommit<'a> {
        EffectCommit {
            items: &[],
            completions,
            current,
            rolled_back_turns: empty,
            identities: &[],
            messages: &[],
            receipts: &[],
            tasks: &[],
            deliveries: &[],
            delivery_repairs: &[],
            attempt: None,
        }
    }
    let effects = [
        CheckpointEffect {
            checkpoint: &first,
            effect: &e1,
            history: history(&c1, &completions1, &empty),
            accounting: AccountingCommit {
                facts: &a1,
                material_changed: false,
            },
        },
        CheckpointEffect {
            checkpoint: &second,
            effect: &e2,
            history: history(&c2, &completions2, &empty),
            accounting: AccountingCommit {
                facts: &a2,
                material_changed: false,
            },
        },
    ];
    store.writer().await?.db.execute_unprepared(
        "CREATE TRIGGER reject_second BEFORE UPDATE ON history_meta
         WHEN NEW.applied_write_seq=2 BEGIN SELECT RAISE(ABORT,'controlled second effect rejection'); END",
    ).await?;
    assert!(store.commit_checkpoint_effects(&effects).await.is_err());
    assert_eq!(store.watermark().await?, 0);
    assert_eq!(store.latest_append_seq().await?, 0);
    assert!(store.checkpoint().await?.is_none());
    assert!(
        checkpoint::read_model_route_head(&store.reader().await?.unwrap().db)
            .await?
            .is_none()
    );
    assert_eq!(
        conversation::current::read(&store.reader().await?.unwrap().db)
            .await?
            .source_effect_seq,
        0
    );
    store
        .writer()
        .await?
        .db
        .execute_unprepared("DROP TRIGGER reject_second")
        .await?;
    assert_eq!(store.commit_checkpoint_effects(&effects).await?.len(), 2);
    assert_eq!(store.watermark().await?, 2);
    let head = checkpoint::read_model_route_head(&store.reader().await?.unwrap().db)
        .await?
        .unwrap();
    assert_eq!(head.revision, 2);
    assert_eq!(head.route.model_id, "second-model");
    assert_eq!(store.latest_append_seq().await?, 2);
    assert_eq!(
        store
            .checkpoint()
            .await?
            .unwrap()
            .state
            .context
            .records
            .len(),
        2
    );
    assert_eq!(
        conversation::current::read(&store.reader().await?.unwrap().db)
            .await?
            .source_effect_seq,
        2
    );
    assert_eq!(store.commit_checkpoint_effects(&effects).await?.len(), 2);
    Ok(())
}

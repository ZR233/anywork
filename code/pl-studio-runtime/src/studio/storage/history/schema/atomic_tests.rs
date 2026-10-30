use super::*;

const THREAD: &str = "atomic-migration";

struct PublishedV9 {
    checkpoint: Option<pl_core::thread::ThreadCheckpoint>,
}

impl MigratorTraitSelf for PublishedV9 {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        Migrator {
            thread_id: THREAD.into(),
            execution_identity: self
                .checkpoint
                .as_ref()
                .map(|checkpoint| (checkpoint.clone(), checkpoint.clone())),
        }
        .migrations()
        .into_iter()
        .filter(|migration| migration.name() != ATOMIC_TIMELINE)
        .collect()
    }
}

async fn v9(path: &Path, cold: bool) -> Result<DatabaseConnection> {
    let db = connect(path, crate::studio::paths::SqliteFileMode::Create).await?;
    let published = PublishedV9 { checkpoint: None };
    let content_steps = published
        .migrations()
        .iter()
        .position(|migration| is_lifecycle_migration(migration.name()))
        .context("published lifecycle boundary")?;
    published
        .up(&db, Some(u32::try_from(content_steps)?))
        .await?;
    if !cold {
        let checkpoint = pl_core::thread::ThreadCheckpoint::capture(
            THREAD.into(),
            0,
            pl_core::thread::ThreadSnapshot::default(),
        );
        checkpoint::write(&db, &checkpoint, None).await?;
        // Lifecycle preparation may normalize the checkpoint before execution identity recovery.
        // Supply the actual post-preparation representation as the explicit recovery candidate.
        let lifecycle_steps = published
            .migrations()
            .iter()
            .position(|migration| migration.name() == EXECUTION_IDENTITY)
            .context("published execution boundary")?
            - content_steps;
        published
            .up(&db, Some(u32::try_from(lifecycle_steps)?))
            .await?;
        let checkpoint = checkpoint::read(&db, THREAD)
            .await?
            .context("prepared recovery checkpoint")?;
        PublishedV9 {
            checkpoint: Some(checkpoint),
        }
        .up(&db, None)
        .await?;
    }
    assert_eq!(version(&db).await?, 9);
    Ok(db)
}

async fn applied(db: &DatabaseConnection, name: &str) -> Result<bool> {
    Ok(db
        .query_one_raw(statement(
            "SELECT 1 FROM seaql_migrations WHERE version=?",
            vec![name.into()],
        ))
        .await?
        .is_some())
}

/// Preserve structural identity and migration records as well as the selected source bodies.
async fn schema_state(db: &DatabaseConnection) -> Result<Vec<String>> {
    let mut state = Vec::new();
    for query in [
        "SELECT json_array(type,name,tbl_name,rootpage,sql) AS fact FROM main.sqlite_schema ORDER BY type,name",
        "SELECT json_array(id,schema_version,database_id,thread_id,applied_write_seq) AS fact FROM history_meta ORDER BY id",
        "SELECT json_array(version,applied_at) AS fact FROM seaql_migrations ORDER BY version",
    ] {
        for row in db.query_all_raw(statement(query, vec![])).await? {
            state.push(row.try_get("", "fact")?);
        }
    }
    Ok(state)
}

#[tokio::test]
async fn atomic_timeline_rejects_v9_identity_column_collation_mismatch() -> Result<()> {
    for populated in [false, true] {
        let directory = tempfile::tempdir()?;
        let db = v9(&directory.path().join("history.sqlite"), true).await?;
        db.execute_unprepared(
            "DROP TABLE history_items;
             CREATE TABLE history_items(
                ordinal INTEGER PRIMARY KEY,item_id TEXT COLLATE NOCASE NOT NULL,
                turn_id TEXT NOT NULL,kind TEXT NOT NULL,revision INTEGER NOT NULL,
                lifecycle TEXT NOT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,
                payload TEXT NOT NULL,last_write_seq INTEGER NOT NULL);
             CREATE UNIQUE INDEX arbitrary_exact_identity ON history_items(item_id COLLATE BINARY)",
        )
        .await?;
        let mut original = Vec::new();
        if populated {
            for (ordinal, identity) in [(1, "A"), (2, "a")] {
                let mut item = ThreadItem::completed_user_message(
                    identity.into(),
                    THREAD.into(),
                    String::new(),
                    format!("preserve {identity}"),
                    vec![],
                    17,
                );
                item.ordinal = ordinal;
                item.revision = 1;
                let payload = serde_json::to_string(&item)?;
                db.execute_raw(statement(
                    "INSERT INTO history_items VALUES(?,?,'','text',1,'terminal',17,17,?,1)",
                    vec![
                        integer(ordinal)?.into(),
                        identity.into(),
                        payload.clone().into(),
                    ],
                ))
                .await?;
                original.push(payload);
            }
            assert_eq!(
                db.query_one_raw(statement(
                    "SELECT COUNT(*) AS hits FROM history_items WHERE item_id='A'",
                    vec![]
                ))
                .await?
                .context("identity lookup")?
                .try_get::<i64>("", "hits")?,
                2,
                "the existing index validation cannot guarantee point-read identity"
            );
        }
        let before = schema_state(&db).await?;
        // Check both cases before preparation: this is a structural defect even in an empty
        // table, not a duplicate-data check or an EXPLAIN-dependent query-plan assertion.
        let error = tokio::time::timeout(Duration::from_secs(10), initialize(&db, THREAD))
            .await?
            .expect_err("v9 initialization must reject mismatched column/index comparison");
        assert!(format!("{error:#}").contains("history_items.item_id requires BINARY"));
        assert_eq!(schema_state(&db).await?, before);
        assert_eq!(version(&db).await?, 9);
        assert!(!applied(&db, ATOMIC_TIMELINE).await?);
        assert!(
            !SchemaManager::new(&db)
                .has_table("timeline_records")
                .await?
        );
        let preserved = db
            .query_all_raw(statement(
                "SELECT payload FROM history_items ORDER BY ordinal",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| row.try_get::<String>("", "payload"))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        assert_eq!(preserved, original);
        db.close().await?;
    }
    Ok(())
}

#[tokio::test]
async fn atomic_timeline_rejects_current_identity_column_collation_mismatch() -> Result<()> {
    for populated in [false, true] {
        let directory = tempfile::tempdir()?;
        let db = v9(&directory.path().join("history.sqlite"), true).await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        db.execute_unprepared(
            "DROP TABLE timeline_records;
             CREATE TABLE timeline_records(
                append_seq INTEGER PRIMARY KEY,record_id TEXT COLLATE NOCASE NOT NULL,
                turn_id TEXT,source_effect_seq INTEGER,sealed_at INTEGER,
                kind TEXT NOT NULL,payload TEXT NOT NULL);
             CREATE UNIQUE INDEX arbitrary_exact_identity ON timeline_records(record_id COLLATE BINARY)",
        )
        .await?;
        if populated {
            db.execute_unprepared(
                "INSERT INTO timeline_records VALUES(1,'A',NULL,NULL,NULL,'text','{\"body\":\"upper\"}');
                 INSERT INTO timeline_records VALUES(2,'a',NULL,NULL,NULL,'text','{\"body\":\"lower\"}')",
            )
            .await?;
            assert_eq!(
                db.query_one_raw(statement(
                    "SELECT COUNT(*) AS hits FROM timeline_records WHERE record_id='A'",
                    vec![]
                ))
                .await?
                .context("identity lookup")?
                .try_get::<i64>("", "hits")?,
                2,
                "two exact identities alias in the default column comparison"
            );
        }
        let before = schema_state(&db).await?;
        let original = db
            .query_all_raw(statement(
                "SELECT payload FROM timeline_records ORDER BY append_seq",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| row.try_get::<String>("", "payload"))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        // A newly opened cold reader does not run preflight. Its own first-connection gate
        // must reject the mismatch before publishing a trusted HistoryConnection.
        let cold = HistoryStore::open(&directory.path().join("history.sqlite"), THREAD).await?;
        let error = tokio::time::timeout(Duration::from_secs(10), cold.latest_append_seq())
            .await?
            .expect_err("independent cold reader must reject mismatched comparison");
        assert!(format!("{error:#}").contains("timeline_records.record_id requires BINARY"));
        assert!(cold.state.reader.get().is_none());
        assert!(cold.state.writer.get().is_none());
        assert_eq!(schema_state(&db).await?, before);
        assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
        assert!(applied(&db, ATOMIC_TIMELINE).await?);
        let preserved = db
            .query_all_raw(statement(
                "SELECT payload FROM timeline_records ORDER BY append_seq",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| row.try_get::<String>("", "payload"))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        assert_eq!(preserved, original);
        db.close().await?;
    }
    Ok(())
}

#[tokio::test]
async fn atomic_timeline_checks_nonunique_turn_identity_and_kind_comparison() -> Result<()> {
    for current in [false, true] {
        for column in ["turn_id", "kind"] {
            for populated in [false, true] {
                let directory = tempfile::tempdir()?;
                let path = directory.path().join("history.sqlite");
                let db = v9(&path, true).await?;
                if current {
                    prepare(&db, THREAD, Preparation::Schema, None).await?;
                }
                let turn_collation = if column == "turn_id" {
                    "COLLATE NOCASE"
                } else {
                    ""
                };
                let kind_collation = if column == "kind" {
                    "COLLATE NOCASE"
                } else {
                    ""
                };
                db.execute_unprepared(&format!(
                    "DROP TABLE history_items;
                     CREATE TABLE history_items(
                        ordinal INTEGER PRIMARY KEY,item_id TEXT NOT NULL UNIQUE,
                        turn_id TEXT {turn_collation} NOT NULL,kind TEXT {kind_collation} NOT NULL,
                        revision INTEGER NOT NULL,lifecycle TEXT NOT NULL,
                        created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,
                        payload TEXT NOT NULL,last_write_seq INTEGER NOT NULL)"
                ))
                .await?;
                let mut original = Vec::new();
                if populated {
                    let mut item = ThreadItem::completed_user_message(
                        "input".into(),
                        THREAD.into(),
                        "Turn-A".into(),
                        "preserve original body".into(),
                        vec![],
                        17,
                    );
                    item.ordinal = 1;
                    item.revision = 1;
                    let payload = serde_json::to_string(&item)?;
                    db.execute_raw(statement(
                        "INSERT INTO history_items VALUES(1,'input','Turn-A','text',1,'terminal',17,17,?,1)",
                        vec![payload.clone().into()],
                    ))
                    .await?;
                    original.push(payload);
                }
                let before = schema_state(&db).await?;
                let error = if current {
                    let cold = HistoryStore::open(&path, THREAD).await?;
                    let error =
                        tokio::time::timeout(Duration::from_secs(10), cold.latest_append_seq())
                            .await?
                            .expect_err(
                                "cold reader must check nonunique identity and selector columns",
                            );
                    assert!(cold.state.reader.get().is_none());
                    error
                } else {
                    tokio::time::timeout(Duration::from_secs(10), initialize(&db, THREAD))
                        .await?
                        .expect_err(
                            "preparation must check nonunique identity and selector columns",
                        )
                };
                assert!(
                    format!("{error:#}")
                        .contains(&format!("history_items.{column} requires BINARY"))
                );
                assert_eq!(schema_state(&db).await?, before);
                assert_eq!(
                    version(&db).await?,
                    if current { HISTORY_SCHEMA_VERSION } else { 9 }
                );
                assert_eq!(applied(&db, ATOMIC_TIMELINE).await?, current);
                assert_eq!(
                    SchemaManager::new(&db)
                        .has_table("timeline_records")
                        .await?,
                    current
                );
                let preserved = db
                    .query_all_raw(statement(
                        "SELECT payload FROM history_items ORDER BY ordinal",
                        vec![],
                    ))
                    .await?
                    .into_iter()
                    .map(|row| row.try_get::<String>("", "payload"))
                    .collect::<std::result::Result<Vec<_>, _>>()?;
                assert_eq!(preserved, original);
                db.close().await?;
            }
        }
    }
    Ok(())
}

#[tokio::test]
async fn atomic_timeline_rejects_nonunique_ordinals_before_backfill_without_mutation() -> Result<()>
{
    let directory = tempfile::tempdir()?;
    let db = v9(&directory.path().join("history.sqlite"), true).await?;
    db.execute_unprepared(
        "DROP TABLE history_items;
         CREATE TABLE history_items (
            ordinal INTEGER NOT NULL,
            item_id TEXT NOT NULL UNIQUE,
            turn_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            revision INTEGER NOT NULL,
            lifecycle TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            payload TEXT NOT NULL CHECK(json_valid(payload)),
            last_write_seq INTEGER NOT NULL
         )",
    )
    .await?;
    // All 260 facts have the same ordinal: a LIMIT 128 + ordinal > last query would lose
    // 132 bodies. They are otherwise valid, complete facts with distinct stable identities.
    let mut original = Vec::new();
    for index in 0..260 {
        let mut item = ThreadItem::completed_user_message(
            format!("input-{index:03}"),
            THREAD.into(),
            String::new(),
            format!("preserve body {index}"),
            vec![],
            17,
        );
        item.ordinal = 7;
        item.revision = 1;
        let payload = serde_json::to_string(&item)?;
        db.execute_raw(statement(
            "INSERT INTO history_items VALUES(7,?,'','text',1,'terminal',17,17,?,1)",
            vec![item.id.into(), payload.clone().into()],
        ))
        .await?;
        original.push(payload);
    }
    assert_eq!(
        db.query_one_raw(statement("PRAGMA quick_check", vec![]))
            .await?
            .context("quick_check")?
            .try_get_by_index::<String>(0)?,
        "ok",
        "integrity checks alone do not establish application key constraints"
    );
    let before = schema_state(&db).await?;
    let error = prepare(&db, THREAD, Preparation::Schema, None)
        .await
        .expect_err("missing ordinal primary key must fail before content DDL");
    assert!(format!("{error:#}").contains("history_items primary key"));
    assert_eq!(schema_state(&db).await?, before);
    assert_eq!(version(&db).await?, 9);
    assert!(!applied(&db, ATOMIC_TIMELINE).await?);
    assert!(
        !SchemaManager::new(&db)
            .has_table("timeline_records")
            .await?
    );
    let preserved = db
        .query_all_raw(statement(
            "SELECT payload FROM history_items ORDER BY item_id",
            vec![],
        ))
        .await?
        .into_iter()
        .map(|row| row.try_get::<String>("", "payload"))
        .collect::<std::result::Result<Vec<_>, _>>()?;
    assert_eq!(preserved, original);
    db.close().await?;
    Ok(())
}

#[tokio::test]
async fn atomic_timeline_identity_affinity_matches_sqlite_type_precedence() -> Result<()> {
    use crate::studio::runtime::chat_item::{completion_draft, encode_record};
    use pl_core::chat::ChatItemParts;

    for current in [false, true] {
        for (declared, allowed, strict) in [
            ("NUMERIC", false, false),
            ("CHARINT", false, false),
            ("TEXT POINT", false, false),
            ("INTEGER", false, false),
            ("REAL", false, false),
            ("BLOB", false, false),
            ("", false, false),
            ("STRING", false, false),
            ("ANY", false, false),
            ("TEXT", true, false),
            ("varchar(32)", true, false),
            ("CLOB", true, false),
            ("BLOB TEXT", true, false),
            ("TEXT", true, true),
            ("ANY", false, true),
        ] {
            for populated in [false, true] {
                let directory = tempfile::tempdir()?;
                let path = directory.path().join("history.sqlite");
                let db = v9(&path, true).await?;
                if current {
                    prepare(&db, THREAD, Preparation::Schema, None).await?;
                }
                let suffix = if strict { " STRICT" } else { "" };
                let (table, identity, sequence) = if current {
                    db.execute_unprepared(&format!(
                        "DROP TABLE timeline_records;
                         CREATE TABLE timeline_records(
                            append_seq INTEGER PRIMARY KEY,record_id {declared} NOT NULL UNIQUE,
                            turn_id TEXT,source_effect_seq INTEGER,sealed_at INTEGER,
                            kind TEXT NOT NULL,payload TEXT NOT NULL){suffix}"
                    ))
                    .await?;
                    ("timeline_records", "record_id", "append_seq")
                } else {
                    db.execute_unprepared(&format!(
                        "DROP TABLE history_items;
                         CREATE TABLE history_items(
                            ordinal INTEGER PRIMARY KEY,item_id {declared} NOT NULL UNIQUE,
                            turn_id TEXT NOT NULL,kind TEXT NOT NULL,revision INTEGER NOT NULL,
                            lifecycle TEXT NOT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,
                            payload TEXT NOT NULL,last_write_seq INTEGER NOT NULL){suffix}"
                    )).await?;
                    ("history_items", "item_id", "ordinal")
                };
                if populated {
                    // The numeric-affinity fixture accepts one original '01' payload; attempting
                    // to insert '1' there would already collapse its identity. Valid TEXT variants
                    // must instead retain both independently, including after v9 backfill.
                    let identities = if allowed {
                        &["01", "1"][..]
                    } else {
                        &["01"][..]
                    };
                    for (index, id) in identities.iter().enumerate() {
                        let mut item = ThreadItem::completed_user_message(
                            (*id).into(),
                            THREAD.into(),
                            String::new(),
                            format!("preserve body {id}"),
                            vec![],
                            17,
                        );
                        item.ordinal = index as u64 + 1;
                        item.revision = 1;
                        if current {
                            let draft = completion_draft(&item, 1)?;
                            let record = ChatItem::complete(ChatItemParts {
                                item_id: draft.item_id,
                                turn_id: draft.turn_id,
                                append_seq: index as u64 + 1,
                                source_effect_seq: draft.source_effect_seq,
                                sealed_at: draft.sealed_at,
                                fields: draft.fields,
                                meta: draft.meta,
                            });
                            db.execute_raw(statement(
                                "INSERT INTO timeline_records VALUES(?,?,NULL,1,17,'text',?)",
                                vec![
                                    integer(record.append_seq)?.into(),
                                    (*id).into(),
                                    encode_record(&record)?.into(),
                                ],
                            ))
                            .await?;
                        } else {
                            db.execute_raw(statement(
                                "INSERT INTO history_items VALUES(?,?,'','text',1,'terminal',17,17,?,1)",
                                vec![integer(item.ordinal)?.into(), (*id).into(), serde_json::to_string(&item)?.into()],
                            )).await?;
                        }
                    }
                }
                let select = format!(
                    "SELECT json_array({sequence},{identity},payload) AS fact FROM {table} ORDER BY {sequence}"
                );
                let original = db
                    .query_all_raw(statement(&select, vec![]))
                    .await?
                    .into_iter()
                    .map(|row| row.try_get::<String>("", "fact"))
                    .collect::<std::result::Result<Vec<_>, _>>()?;
                let before = schema_state(&db).await?;
                let cold = HistoryStore::open(&path, THREAD).await?;
                let result = if current {
                    tokio::time::timeout(Duration::from_secs(10), cold.latest_append_seq())
                        .await
                        .map(|result| result.map(|_| ()))
                } else {
                    tokio::time::timeout(Duration::from_secs(10), initialize(&db, THREAD))
                        .await
                        .map(|result| result.map(|_| ()))
                }?;
                if allowed {
                    result?;
                    assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
                    let expected = if populated { 2 } else { 0 };
                    assert_eq!(cold.latest_append_seq().await?, expected);
                    if populated {
                        for id in ["01", "1"] {
                            let hits = db
                                .query_one_raw(statement(
                                    &format!(
                                        "SELECT COUNT(*) AS hits FROM {table} WHERE {identity}=?"
                                    ),
                                    vec![id.into()],
                                ))
                                .await?
                                .context("exact identity lookup")?
                                .try_get::<i64>("", "hits")?;
                            assert_eq!(hits, 1, "{declared} must keep {id} distinct");
                            assert_eq!(
                                cold.read_chat_item(id)
                                    .await?
                                    .context("completed identity")?
                                    .item_id,
                                id
                            );
                        }
                    }
                } else {
                    let error = result.expect_err("non-TEXT identity affinity must be rejected");
                    assert!(
                        format!("{error:#}")
                            .contains(&format!("{table}.{identity} requires TEXT affinity")),
                        "declared={declared:?}, strict={strict}, current={current}: {error:#}"
                    );
                    assert_eq!(schema_state(&db).await?, before);
                    assert_eq!(
                        version(&db).await?,
                        if current { HISTORY_SCHEMA_VERSION } else { 9 }
                    );
                    assert_eq!(applied(&db, ATOMIC_TIMELINE).await?, current);
                    assert_eq!(
                        SchemaManager::new(&db)
                            .has_table("timeline_records")
                            .await?,
                        current
                    );
                    assert!(cold.state.reader.get().is_none());
                }
                let preserved = db
                    .query_all_raw(statement(&select, vec![]))
                    .await?
                    .into_iter()
                    .map(|row| row.try_get::<String>("", "fact"))
                    .collect::<std::result::Result<Vec<_>, _>>()?;
                assert_eq!(preserved, original);
                db.close().await?;
            }
        }
    }
    Ok(())
}

#[tokio::test]
async fn atomic_timeline_validates_all_v9_write_keys_and_semantic_unique_indexes() -> Result<()> {
    // CTAS preserves every queried column while removing constraints. Every listed table has a
    // key used by this history writer or its checkpoint transaction, even when the table is empty.
    for table in [
        "history_meta",
        "history_items",
        "history_turns",
        "history_input_identities",
        "history_fact_receipts",
        "history_message_identities",
        "session_checkpoint",
        "session_costs",
        "current_context",
        "history_tool_tasks",
    ] {
        let directory = tempfile::tempdir()?;
        let db = v9(&directory.path().join("history.sqlite"), true).await?;
        db.execute_unprepared(&format!(
            "CREATE TABLE missing_keys AS SELECT * FROM {table};
             DROP TABLE {table}; ALTER TABLE missing_keys RENAME TO {table}"
        ))
        .await?;
        let before = schema_state(&db).await?;
        let error = prepare(&db, THREAD, Preparation::Schema, None)
            .await
            .expect_err("same columns without primary keys must not be adopted");
        assert!(format!("{error:#}").contains(&format!("table {table} primary key")));
        assert_eq!(schema_state(&db).await?, before);
        assert!(
            !SchemaManager::new(&db)
                .has_table("timeline_records")
                .await?
        );
        db.close().await?;
    }
    // Rowid composite primary keys are not implicitly NOT NULL. Exercise each component
    // independently, empty and populated, through both production trust boundaries.
    for current in [false, true] {
        for (table, keys) in [
            ("history_fact_receipts", ["item_id", "revision"]),
            ("session_costs", ["purpose", "currency"]),
        ] {
            for missing in keys {
                for populated in [false, true] {
                    let directory = tempfile::tempdir()?;
                    let path = directory.path().join("history.sqlite");
                    let db = v9(&path, true).await?;
                    if current {
                        prepare(&db, THREAD, Preparation::Schema, None).await?;
                    }
                    let first_notnull = if missing == keys[0] { "" } else { "NOT NULL" };
                    let second_notnull = if missing == keys[1] { "" } else { "NOT NULL" };
                    let (ddl, insert, select) = if table == "history_fact_receipts" {
                        let values = if missing == "item_id" {
                            "NULL,1"
                        } else {
                            "'receipt',NULL"
                        };
                        (
                            format!(
                                "CREATE TABLE history_fact_receipts(
                                    item_id TEXT {first_notnull},revision INTEGER {second_notnull},
                                    kind TEXT NOT NULL,digest TEXT NOT NULL,payload TEXT NOT NULL,
                                    last_write_seq INTEGER NOT NULL,PRIMARY KEY(item_id,revision))"
                            ),
                            format!(
                                "INSERT INTO history_fact_receipts VALUES({values},'interaction','digest','{{\"body\":\"first\"}}',1);
                                 INSERT INTO history_fact_receipts VALUES({values},'interaction','digest','{{\"body\":\"second\"}}',1)"
                            ),
                            "SELECT json_array(item_id,revision,kind,digest,payload,last_write_seq) AS fact FROM history_fact_receipts ORDER BY rowid",
                        )
                    } else {
                        let values = if missing == "purpose" {
                            "NULL,'CNY'"
                        } else {
                            "'null',NULL"
                        };
                        (
                            format!(
                                "CREATE TABLE session_costs(
                                    purpose TEXT {first_notnull},currency TEXT {second_notnull},
                                    amount REAL NOT NULL,PRIMARY KEY(purpose,currency))"
                            ),
                            format!(
                                "INSERT INTO session_costs VALUES({values},1.25);
                                 INSERT INTO session_costs VALUES({values},2.5)"
                            ),
                            "SELECT json_array(purpose,currency,amount) AS fact FROM session_costs ORDER BY rowid",
                        )
                    };
                    db.execute_unprepared(&format!("DROP TABLE {table}; {ddl}"))
                        .await?;
                    if populated {
                        db.execute_unprepared(&insert).await?;
                    }
                    let original = db
                        .query_all_raw(statement(select, vec![]))
                        .await?
                        .into_iter()
                        .map(|row| row.try_get::<String>("", "fact"))
                        .collect::<std::result::Result<Vec<_>, _>>()?;
                    assert_eq!(original.len(), if populated { 2 } else { 0 });
                    let before = schema_state(&db).await?;
                    let error = if current {
                        let cold = HistoryStore::open(&path, THREAD).await?;
                        let error =
                            tokio::time::timeout(Duration::from_secs(10), cold.latest_append_seq())
                                .await?
                                .expect_err("cold reader must reject nullable composite key");
                        assert!(cold.state.reader.get().is_none());
                        error
                    } else {
                        tokio::time::timeout(Duration::from_secs(10), initialize(&db, THREAD))
                            .await?
                            .expect_err("v9 preparation must reject nullable composite key")
                    };
                    assert!(
                        format!("{error:#}").contains(&format!(
                            "table {table} composite primary key column {missing} requires NOT NULL"
                        )),
                        "{error:#}"
                    );
                    assert_eq!(schema_state(&db).await?, before);
                    assert_eq!(
                        version(&db).await?,
                        if current { HISTORY_SCHEMA_VERSION } else { 9 }
                    );
                    assert_eq!(applied(&db, ATOMIC_TIMELINE).await?, current);
                    assert_eq!(
                        SchemaManager::new(&db)
                            .has_table("timeline_records")
                            .await?,
                        current
                    );
                    let preserved = db
                        .query_all_raw(statement(select, vec![]))
                        .await?
                        .into_iter()
                        .map(|row| row.try_get::<String>("", "fact"))
                        .collect::<std::result::Result<Vec<_>, _>>()?;
                    assert_eq!(preserved, original);
                    db.close().await?;
                }
            }
        }
    }
    for unique_index in [
        "",
        "CREATE UNIQUE INDEX arbitrary ON history_items(item_id) WHERE ordinal>0",
        "CREATE UNIQUE INDEX arbitrary ON history_items(lower(item_id))",
        "CREATE UNIQUE INDEX arbitrary ON history_items(item_id,turn_id)",
        "CREATE UNIQUE INDEX arbitrary ON history_items(item_id COLLATE NOCASE)",
        "CREATE INDEX arbitrary ON history_items(item_id)",
        "CREATE UNIQUE INDEX arbitrary ON history_items(item_id)",
    ] {
        let directory = tempfile::tempdir()?;
        let db = v9(&directory.path().join("history.sqlite"), true).await?;
        db.execute_unprepared(
            "DROP TABLE history_items;
             CREATE TABLE history_items (
                ordinal INTEGER PRIMARY KEY,item_id TEXT NOT NULL,turn_id TEXT NOT NULL,
                kind TEXT NOT NULL,revision INTEGER NOT NULL,lifecycle TEXT NOT NULL,
                created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,payload TEXT NOT NULL,
                last_write_seq INTEGER NOT NULL)",
        )
        .await?;
        if !unique_index.is_empty() {
            db.execute_unprepared(unique_index).await?;
        }
        let before = schema_state(&db).await?;
        let result = prepare(&db, THREAD, Preparation::Schema, None).await;
        if unique_index == "CREATE UNIQUE INDEX arbitrary ON history_items(item_id)" {
            result?;
            validate_current(&db, THREAD).await?;
        } else {
            assert!(
                result.is_err(),
                "must reject insufficient index: {unique_index}"
            );
            assert_eq!(schema_state(&db).await?, before);
            assert!(
                !SchemaManager::new(&db)
                    .has_table("timeline_records")
                    .await?
            );
        }
        db.close().await?;
    }
    Ok(())
}

#[tokio::test]
async fn atomic_timeline_rejects_damaged_current_keys_without_repair() -> Result<()> {
    for key_ddl in [
        "append_seq INTEGER,record_id TEXT NOT NULL UNIQUE",
        "append_seq INT PRIMARY KEY,record_id TEXT NOT NULL UNIQUE",
        "append_seq INTEGER PRIMARY KEY DESC,record_id TEXT NOT NULL UNIQUE",
        "append_seq INTEGER PRIMARY KEY,record_id TEXT NOT NULL",
        "append_seq INTEGER PRIMARY KEY,record_id TEXT UNIQUE",
    ] {
        let directory = tempfile::tempdir()?;
        let db = v9(&directory.path().join("history.sqlite"), true).await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        db.execute_unprepared(&format!(
            "DROP TABLE timeline_records;
             CREATE TABLE timeline_records(
                {key_ddl},turn_id TEXT,source_effect_seq INTEGER,sealed_at INTEGER,
                kind TEXT NOT NULL,payload TEXT NOT NULL);
             INSERT INTO timeline_records VALUES(1,'preserved',NULL,NULL,NULL,'text','{{}}')"
        ))
        .await?;
        let before = schema_state(&db).await?;
        assert!(validate_current(&db, THREAD).await.is_err());
        assert!(
            prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .is_err()
        );
        assert_eq!(schema_state(&db).await?, before);
        assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
        assert!(applied(&db, ATOMIC_TIMELINE).await?);
        let payload: String = db
            .query_one_raw(statement(
                "SELECT payload FROM timeline_records WHERE record_id='preserved'",
                vec![],
            ))
            .await?
            .context("unchanged damaged timeline source")?
            .try_get("", "payload")?;
        assert_eq!(payload, "{}");
        db.close().await?;
    }
    Ok(())
}

#[tokio::test]
async fn atomic_timeline_upgrades_complete_v9_and_pending_cold_store() -> Result<()> {
    for cold in [false, true] {
        let directory = tempfile::tempdir()?;
        let db = v9(&directory.path().join("history.sqlite"), cold).await?;
        preflight(&db, THREAD).await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        assert_eq!(version(&db).await?, HISTORY_SCHEMA_VERSION);
        assert!(applied(&db, ATOMIC_TIMELINE).await?);
        assert_eq!(applied(&db, PROJECT_KIND).await?, !cold);
        assert_eq!(applied(&db, MODEL_ACCESS).await?, !cold);
        validate_current(&db, THREAD).await?;
        assert_eq!(super::super::timeline::latest_append_seq(&db).await?, 0);
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        assert_eq!(super::super::timeline::latest_append_seq(&db).await?, 0);
        db.close().await?;
    }
    Ok(())
}

#[tokio::test]
async fn atomic_timeline_preserves_published_v8_adoption() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let db = v9(&directory.path().join("history.sqlite"), true).await?;
    db.execute_unprepared(
        "DROP TABLE seaql_migrations;
         UPDATE history_meta SET schema_version=8;
         CREATE TABLE history_ordinals(item_id TEXT PRIMARY KEY,ordinal INTEGER NOT NULL)",
    )
    .await?;
    prepare(&db, THREAD, Preparation::Schema, None).await?;
    validate_current(&db, THREAD).await?;
    assert!(
        !SchemaManager::new(&db)
            .has_table("history_ordinals")
            .await?
    );
    assert!(applied(&db, RETIRE_ORDINALS).await?);
    assert!(applied(&db, ATOMIC_TIMELINE).await?);
    db.close().await?;
    Ok(())
}

#[tokio::test]
async fn atomic_timeline_rejects_marker_schema_and_identity_conflicts() -> Result<()> {
    for corruption in [
        "UPDATE history_meta SET schema_version=10",
        "INSERT INTO seaql_migrations(version,applied_at) VALUES('m20261027_000004_history_atomic_timeline',0)",
        "CREATE TABLE timeline_records(append_seq INTEGER PRIMARY KEY)",
        "DROP TABLE history_tool_tasks",
        "UPDATE history_meta SET schema_version=999",
        "UPDATE history_meta SET thread_id='other-thread'",
    ] {
        let directory = tempfile::tempdir()?;
        let db = v9(&directory.path().join("history.sqlite"), true).await?;
        db.execute_unprepared(corruption).await?;
        assert!(
            preflight(&db, THREAD).await.is_err(),
            "must reject {corruption}"
        );
        db.close().await?;
    }
    for corruption in [
        "DELETE FROM seaql_migrations WHERE version='m20261027_000004_history_atomic_timeline'",
        "UPDATE history_meta SET schema_version=9",
        "DROP TABLE timeline_records",
    ] {
        let directory = tempfile::tempdir()?;
        let db = v9(&directory.path().join("history.sqlite"), true).await?;
        prepare(&db, THREAD, Preparation::Schema, None).await?;
        db.execute_unprepared(corruption).await?;
        assert!(
            preflight(&db, THREAD).await.is_err(),
            "must reject {corruption}"
        );
        db.close().await?;
    }
    Ok(())
}

#[tokio::test]
async fn atomic_timeline_ddl_marker_and_backfill_roll_back_then_retry() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let db = v9(&directory.path().join("history.sqlite"), true).await?;
    let mut input = ThreadItem::completed_user_message(
        "input".into(),
        THREAD.into(),
        String::new(),
        "保留正文\n  indentation".into(),
        vec![],
        17,
    );
    input.ordinal = 41;
    input.revision = 3;
    HistoryStore::open(&directory.path().join("unused.sqlite"), THREAD)
        .await?
        .upsert_item(&db, 1, input.clone())
        .await?;
    db.execute_unprepared(
        "CREATE TRIGGER fail_atomic_marker BEFORE UPDATE OF schema_version ON history_meta
         WHEN NEW.schema_version=10
         BEGIN SELECT RAISE(ABORT,'injected atomic marker failure'); END",
    )
    .await?;
    let error = prepare(&db, THREAD, Preparation::Schema, None)
        .await
        .expect_err("schema marker failure must roll back the whole content step");
    assert!(format!("{error:#}").contains("injected atomic marker failure"));
    assert_eq!(version(&db).await?, 9);
    assert!(
        !SchemaManager::new(&db)
            .has_table("timeline_records")
            .await?
    );
    assert!(!applied(&db, ATOMIC_TIMELINE).await?);
    let payload: String = db
        .query_one_raw(statement("SELECT payload FROM history_items", vec![]))
        .await?
        .context("original fact")?
        .try_get("", "payload")?;
    assert_eq!(serde_json::from_str::<ThreadItem>(&payload)?, input);
    db.execute_unprepared("DROP TRIGGER fail_atomic_marker")
        .await?;
    prepare(&db, THREAD, Preparation::Schema, None).await?;
    assert_eq!(super::super::timeline::latest_append_seq(&db).await?, 1);
    prepare(&db, THREAD, Preparation::Schema, None).await?;
    assert_eq!(super::super::timeline::latest_append_seq(&db).await?, 1);
    db.close().await?;
    Ok(())
}

#[tokio::test]
async fn atomic_timeline_conversion_failure_preserves_source_and_retries() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let db = v9(&directory.path().join("history.sqlite"), true).await?;
    let store = HistoryStore::open(&directory.path().join("history.sqlite"), THREAD).await?;
    let mut items = Vec::new();
    for ordinal in [1, 2] {
        let mut item = ThreadItem::completed_user_message(
            format!("input-{ordinal}"),
            THREAD.into(),
            String::new(),
            format!("original body {ordinal}"),
            vec![],
            17,
        );
        item.ordinal = ordinal;
        item.revision = 1;
        store.upsert_item(&db, 1, item.clone()).await?;
        items.push(item);
    }
    let corrupt = r#"{"unexpected":"preserve this invalid source verbatim"}"#;
    db.execute_raw(statement(
        "UPDATE history_items SET payload=? WHERE ordinal=2",
        vec![corrupt.into()],
    ))
    .await?;
    assert!(
        prepare(&db, THREAD, Preparation::Schema, None)
            .await
            .is_err()
    );
    assert_eq!(version(&db).await?, 9);
    assert!(
        !SchemaManager::new(&db)
            .has_table("timeline_records")
            .await?
    );
    assert!(!applied(&db, ATOMIC_TIMELINE).await?);
    let saved: String = db
        .query_one_raw(statement(
            "SELECT payload FROM history_items WHERE ordinal=2",
            vec![],
        ))
        .await?
        .context("preserved invalid source")?
        .try_get("", "payload")?;
    assert_eq!(saved, corrupt);
    db.execute_raw(statement(
        "UPDATE history_items SET payload=? WHERE ordinal=2",
        vec![serde_json::to_string(&items[1])?.into()],
    ))
    .await?;
    prepare(&db, THREAD, Preparation::Schema, None).await?;
    let page = super::super::timeline::page(&db, THREAD, None, 2, 10).await?;
    assert_eq!(
        page.items
            .iter()
            .map(|item| (item.item_id.as_str(), item.append_seq))
            .collect::<Vec<_>>(),
        [("input-1", 1), ("input-2", 2)]
    );
    db.close().await?;
    Ok(())
}

#[tokio::test]
async fn atomic_timeline_backfill_order_content_and_frozen_reads() -> Result<()> {
    use pl_protocol::{
        AttachmentModality, QueuedThreadTool, ThreadAttachment, ThreadContentLifecycle,
        ThreadTextChannel, ThreadTextItem, ThreadThinkingItem, ThreadToolInvocation,
        ThreadToolItem, ThreadToolState, ThreadToolUserInput, ThreadToolUserInputState,
        UserQuestion,
    };
    let directory = tempfile::tempdir()?;
    let db = v9(&directory.path().join("history.sqlite"), true).await?;
    let store = HistoryStore::open(&directory.path().join("history.sqlite"), THREAD).await?;
    let attachment = ThreadAttachment {
        id: "attachment-original".into(),
        modality: AttachmentModality::File,
        media_type: "text/plain".into(),
        filename: Some("原附件.txt".into()),
        width: None,
        height: None,
        byte_size: 19,
    };
    let mut input = ThreadItem::completed_user_message(
        "accepted".into(),
        THREAD.into(),
        String::new(),
        "原文\n  不裁剪".into(),
        vec![attachment.clone()],
        17,
    );
    input.ordinal = 20;
    input.revision = 1;
    input.updated_at = 9999;
    let thinking = ThreadItem::new(
        "thinking".into(),
        THREAD.into(),
        "turn".into(),
        30,
        1,
        18,
        9999,
        ThreadItemState::Thinking(ThreadThinkingItem::new(
            vec!["第一段".into(), "第二段".into()],
            vec![],
            ThreadContentLifecycle::completed(19),
        )),
    );
    let running = ThreadItem::new(
        "still-running".into(),
        THREAD.into(),
        "turn".into(),
        25,
        1,
        18,
        9999,
        ThreadItemState::Text(ThreadTextItem::new(
            ThreadTextChannel::Final,
            "尚未可靠完成".into(),
            vec![],
            ThreadContentLifecycle::streaming(),
        )),
    );
    let pending = ThreadItem::new(
        "pending-question".into(),
        THREAD.into(),
        "turn".into(),
        26,
        1,
        18,
        9999,
        ThreadItemState::Tool(
            ThreadToolItem::new(
                ThreadToolInvocation::new("question-call".into(), "ask".into(), "{}".into()),
                ThreadToolState::Queued(QueuedThreadTool),
            )
            .with_user_input(Some(ThreadToolUserInput::new(
                "interaction".into(),
                vec![UserQuestion {
                    id: "question".into(),
                    header: "待决".into(),
                    question: "尚未回答？".into(),
                    is_other: false,
                    is_secret: false,
                    options: None,
                }],
                ThreadToolUserInputState::Pending,
            ))),
        ),
    );
    // Insert out of order: migration order comes from the durable ordinal, not insertion order.
    for item in [&thinking, &running, &input, &pending] {
        store.upsert_item(&db, 7, item.clone()).await?;
    }
    let original: Vec<String> = db
        .query_all_raw(statement(
            "SELECT payload FROM history_items ORDER BY ordinal",
            vec![],
        ))
        .await?
        .into_iter()
        .map(|row| row.try_get("", "payload"))
        .collect::<std::result::Result<_, _>>()?;
    prepare(&db, THREAD, Preparation::Schema, None).await?;
    let page = super::super::timeline::page(&db, THREAD, None, 3, 10).await?;
    assert_eq!(page.items.len(), 3);
    assert!(!page.has_more);
    assert_eq!(page.items[0].item_id, input.id);
    assert_eq!(page.items[0].turn_id, None);
    for (position, item) in page.items.iter().enumerate() {
        assert_eq!(item.append_seq, position as u64 + 1);
        assert_eq!(
            item.source_effect_seq, None,
            "last_write_seq is not provenance"
        );
        assert_eq!(item.sealed_at, None, "updated_at is not first seal time");
    }
    let bodies = page
        .items
        .iter()
        .map(|item| {
            item.fields
                .values()
                .map(|field| field.block.text())
                .collect::<Vec<_>>()
                .join("")
        })
        .collect::<Vec<_>>();
    assert_eq!(bodies, ["原文\n  不裁剪", "第一段", "第二段"]);
    let input_meta =
        crate::studio::runtime::timeline_content::meta::TimelineMeta::for_item(&page.items[0])?;
    let pl_protocol::TimelineDescriptor::Text(text) = input_meta.descriptor else {
        anyhow::bail!("input completion lost its text descriptor");
    };
    assert_eq!(text.attachments, [attachment]);
    let after: Vec<String> = db
        .query_all_raw(statement(
            "SELECT payload FROM history_items ORDER BY ordinal",
            vec![],
        ))
        .await?
        .into_iter()
        .map(|row| row.try_get("", "payload"))
        .collect::<std::result::Result<_, _>>()?;
    assert_eq!(
        after, original,
        "content migration never rewrites execution facts"
    );
    let cursor = ChatCursor::of(
        &pl_core::chat::TimelineEpoch::new("migration-test")?,
        &page.items[2],
    );
    let older = super::super::timeline::page(&db, THREAD, Some(&cursor), 3, 1).await?;
    assert_eq!(older.items[0], page.items[1]);
    assert!(older.has_more);
    let catchup = super::super::timeline::page_after(&db, THREAD, 0, 2, 1).await?;
    assert_eq!(catchup.items, page.items[..1]);
    assert!(catchup.has_more);
    assert_eq!(
        super::super::timeline::read_item(&db, THREAD, &page.items[1].item_id).await?,
        Some(page.items[1].clone())
    );
    let mut invalid = cursor;
    invalid.item_id = "wrong-identity".into();
    assert!(
        super::super::timeline::page(&db, THREAD, Some(&invalid), 3, 1)
            .await
            .is_err()
    );
    assert!(
        super::super::timeline::page(&db, THREAD, None, 3, 0)
            .await
            .is_err()
    );
    super::super::timeline::append_records(&db, THREAD, &page.items, false).await?;
    let mut conflicting = page.items[0].clone();
    conflicting.sealed_at = Some(123456);
    assert!(
        super::super::timeline::append_records(&db, THREAD, &[conflicting], false)
            .await
            .is_err()
    );
    db.close().await?;
    Ok(())
}

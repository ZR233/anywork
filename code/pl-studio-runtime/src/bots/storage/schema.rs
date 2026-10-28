//! SQLite ledger initialization and legacy import owned by the official migrator.
use super::*;
use sea_orm_migration::{DbErr, MigrationName, MigrationTrait, MigratorTraitSelf, SchemaManager};

mod lineage;
mod preflight;
mod steps;

pub(super) async fn inspect_existing(path: &Path) -> anyhow::Result<()> {
    if !tokio::fs::try_exists(path).await? {
        return Ok(());
    }
    let options = sqlite_file_options(path, SqliteFileMode::ReadOnly, |options| options).await?;
    let db = Database::connect(options).await?;
    let result = preflight::inspect(&db, DatabaseOrigin::Existing)
        .await
        .map(|_| ())
        .map_err(|error| crate::studio::startup::migration_error("bot ledger", "preflight", error));
    let close = db.close().await;
    result?;
    close?;
    Ok(())
}

pub(super) async fn initialize(
    db: &DatabaseConnection,
    origin: DatabaseOrigin,
) -> anyhow::Result<()> {
    let migrator = preflight::inspect(db, origin).await.map_err(|error| {
        crate::studio::startup::migration_error("bot ledger", "preflight", error)
    })?;
    // The official pending sequence is the scheduler. Applying one official step at a time only
    // preserves precise failure ownership; format numbers never choose the next conversion.
    let pending = migrator
        .get_pending_migrations_read_only(db)
        .await
        .map_err(|error| {
            crate::studio::startup::migration_error("bot ledger", "preflight", error)
        })?;
    for step in pending {
        migrator.up(db, Some(1)).await.map_err(|error| {
            crate::studio::startup::migration_error("bot ledger", step.name(), error)
        })?;
    }
    Ok(())
}
struct LedgerSchema;
impl MigrationName for LedgerSchema {
    fn name(&self) -> &str {
        "m20261026_000001_bot_ledger_schema"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for LedgerSchema {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS bot_meta (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            schema_version INTEGER NOT NULL
        )",
        )
        .await?;
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS inbound_identities (
            identity TEXT PRIMARY KEY,
            bot_id TEXT NOT NULL DEFAULT '',
            message_id TEXT NOT NULL,
            chat_id TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            admitted_at INTEGER NOT NULL
        )",
        )
        .await?;
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS inbound_work (
            identity TEXT PRIMARY KEY,
            bot_id TEXT NOT NULL DEFAULT '',
            chat_id TEXT NOT NULL DEFAULT '',
            message_id TEXT NOT NULL DEFAULT '',
            content_hash TEXT NOT NULL DEFAULT '',
            text TEXT NOT NULL DEFAULT '',
            open_id TEXT NOT NULL DEFAULT '',
            chat_kind TEXT NOT NULL DEFAULT '',
            generation INTEGER NOT NULL DEFAULT 0,
            app_id TEXT NOT NULL DEFAULT '',
            project_id TEXT NOT NULL DEFAULT '',
            creation_id TEXT NOT NULL DEFAULT '',
            binding_revision INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL,
            diagnostic TEXT NOT NULL,
            claimed_by TEXT NOT NULL DEFAULT '',
            claimed_at INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL
        )",
        )
        .await?;
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS thread_bindings (
            chat_id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'bound',
            creation_id TEXT NOT NULL DEFAULT '',
            project_id TEXT NOT NULL DEFAULT '',
            revision INTEGER NOT NULL DEFAULT 0,
            generation INTEGER NOT NULL DEFAULT 0,
            diagnostic TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL DEFAULT 0
        )",
        )
        .await?;
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS observed_directs (
            chat_id TEXT PRIMARY KEY,
            open_id TEXT NOT NULL,
            name TEXT NOT NULL,
            last_observed_at INTEGER NOT NULL
        )",
        )
        .await?;
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS pairing_requests (
            request_id TEXT PRIMARY KEY,
            open_id TEXT NOT NULL,
            display_name TEXT NOT NULL,
            created_at INTEGER NOT NULL
        )",
        )
        .await?;
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS send_operations (
            operation_id TEXT PRIMARY KEY,
            bot_id TEXT NOT NULL DEFAULT '',
            chat_id TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            status TEXT NOT NULL,
            platform_message_ids TEXT NOT NULL,
            updated_at INTEGER NOT NULL
        )",
        )
        .await?;
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS binding_operations (
            operation_id TEXT PRIMARY KEY,
            bot_id TEXT NOT NULL,
            chat_id TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            expected_revision INTEGER NOT NULL,
            creation_id TEXT NOT NULL,
            thread_id TEXT NOT NULL DEFAULT '',
            updated_at INTEGER NOT NULL
        )",
        )
        .await?;
        adopt_legacy_ledger(db)
            .await
            .map_err(|error| match error.downcast::<DbErr>() {
                Ok(error) => error,
                Err(error) => DbErr::Migration(format!("{error:#}")),
            })?;
        Ok(())
    }
}

async fn adopt_legacy_ledger<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    let version = db
        .query_one_raw(statement(
            "SELECT schema_version FROM bot_meta WHERE id=1",
            vec![],
        ))
        .await?;
    if let Some(version) = version {
        let version: i64 = version.try_get("", "schema_version")?;
        anyhow::ensure!(version <= 6, "unsupported future bot state schema");
    }
    create_card_streams_v6(db).await?;
    db.execute_unprepared(
        "CREATE UNIQUE INDEX IF NOT EXISTS pairing_open_id ON pairing_requests(open_id)",
    )
    .await?;
    ensure_column(
        db,
        "inbound_identities",
        "bot_id",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(db, "inbound_work", "bot_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(db, "inbound_work", "chat_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(db, "inbound_work", "message_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "inbound_work",
        "content_hash",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(db, "inbound_work", "text", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "inbound_work",
        "attachments",
        "TEXT NOT NULL DEFAULT '[]'",
    )
    .await?;
    ensure_column(db, "inbound_work", "open_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(db, "inbound_work", "chat_kind", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "inbound_work",
        "generation",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(db, "inbound_work", "app_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(db, "inbound_work", "project_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "inbound_work",
        "creation_id",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(
        db,
        "inbound_work",
        "binding_revision",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(db, "inbound_work", "claimed_by", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "inbound_work",
        "claimed_at",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(
        db,
        "inbound_work",
        "watch_input",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(
        db,
        "inbound_work",
        "attempt_count",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(
        db,
        "inbound_work",
        "next_attempt_at",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "status",
        "TEXT NOT NULL DEFAULT 'bound'",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "creation_id",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "project_id",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "revision",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "generation",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "diagnostic",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    ensure_column(
        db,
        "thread_bindings",
        "updated_at",
        "INTEGER NOT NULL DEFAULT 0",
    )
    .await?;
    ensure_column(db, "send_operations", "bot_id", "TEXT NOT NULL DEFAULT ''").await?;
    ensure_column(
        db,
        "send_operations",
        "segment_facts",
        "TEXT NOT NULL DEFAULT ''",
    )
    .await?;
    // 旧 pending 与“creating 但缺创建身份”的行一律规范为 needs_attention：
    // 不从 thread_id 反推创建身份，运行时也不再重新兼容这两种值。
    db.execute_unprepared(
        "UPDATE thread_bindings
         SET status='needs_attention',
             diagnostic='legacy pending binding requires local recreate',
             revision=CASE WHEN revision=0 THEN 1 ELSE revision END
         WHERE thread_id='pending' OR status='pending' OR (status='creating' AND creation_id='')",
    )
    .await?;
    db.execute_unprepared(
        "UPDATE inbound_work
         SET status='needs_attention',
             diagnostic='legacy inbound lacks frozen binding identity'
         WHERE status IN ('pending','claimed','failed')
           AND (creation_id='' OR app_id='' OR project_id='')",
    )
    .await?;
    db.execute_unprepared(
        "UPDATE thread_bindings SET revision=1, generation=1 WHERE revision=0 AND status='bound'",
    )
    .await?;
    db.execute_raw(statement(
        "INSERT INTO bot_meta(id, schema_version) VALUES(1, ?)
         ON CONFLICT(id) DO UPDATE SET schema_version=excluded.schema_version",
        vec![6i64.into()],
    ))
    .await?;
    Ok(())
}

async fn ensure_column<C: ConnectionTrait>(
    db: &C,
    table: &str,
    column: &str,
    decl: &str,
) -> anyhow::Result<()> {
    let columns = db
        .query_all_raw(statement(&format!("PRAGMA table_info({table})"), vec![]))
        .await?;
    let present = columns
        .iter()
        .any(|row| row.try_get::<String>("", "name").ok().as_deref() == Some(column));
    if !present {
        db.execute_unprepared(&format!("ALTER TABLE {table} ADD COLUMN {column} {decl}"))
            .await?;
    }
    Ok(())
}

async fn create_card_streams_v6<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    db.execute_unprepared(
        "CREATE TABLE IF NOT EXISTS bot_card_streams (
            identity TEXT PRIMARY KEY,
            bot_id TEXT NOT NULL, chat_id TEXT NOT NULL, message_id TEXT NOT NULL,
            thread_id TEXT NOT NULL, original_input TEXT NOT NULL,
            watch_input TEXT NOT NULL, turn_id TEXT NOT NULL,
            version INTEGER NOT NULL CHECK(version>0), state_json TEXT NOT NULL,
            updated_at INTEGER NOT NULL
        )",
    )
    .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    //! Real SQLite migration/save regressions: official records and source bytes are part of the
    //! recovery contract. These fixtures never authorize production to ignore an inconsistent log.
    use super::lineage::{Format, Migrator};
    use super::*;

    async fn memory() -> anyhow::Result<DatabaseConnection> {
        Ok(Database::connect("sqlite::memory:").await?)
    }

    async fn version(db: &DatabaseConnection) -> anyhow::Result<i64> {
        Ok(db
            .query_one_raw(statement(
                "SELECT schema_version FROM bot_meta WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get("", "schema_version")?)
    }

    async fn names(db: &DatabaseConnection, migrator: Migrator) -> anyhow::Result<Vec<String>> {
        Ok(migrator
            .get_applied_migrations_read_only(db)
            .await?
            .into_iter()
            .map(|step| step.name().to_owned())
            .collect())
    }

    async fn declarations(
        db: &DatabaseConnection,
    ) -> anyhow::Result<Vec<(String, Option<String>)>> {
        Ok(db
            .query_all_raw(statement(
                "SELECT name,sql FROM sqlite_schema ORDER BY name",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| Ok((row.try_get("", "name")?, row.try_get("", "sql")?)))
            .collect::<Result<_, sea_orm::DbErr>>()?)
    }

    async fn official_records(db: &DatabaseConnection) -> anyhow::Result<Vec<(String, i64)>> {
        if db
            .query_one_raw(statement(
                "SELECT 1 FROM sqlite_schema WHERE name='seaql_migrations'",
                vec![],
            ))
            .await?
            .is_none()
        {
            return Ok(Vec::new());
        }
        Ok(db
            .query_all_raw(statement(
                "SELECT version,applied_at FROM seaql_migrations ORDER BY version",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| Ok((row.try_get("", "version")?, row.try_get("", "applied_at")?)))
            .collect::<Result<_, sea_orm::DbErr>>()?)
    }

    #[tokio::test]
    async fn official_steps_preserve_committed_prefix_and_retry_only_the_failed_boundary()
    -> anyhow::Result<()> {
        for (failing_version, completed, step) in [
            (8, 1, lineage::FILE8),
            (9, 2, lineage::AUDIENCE9),
            (10, 3, lineage::PUBLICATION10),
        ] {
            let db = memory().await?;
            Migrator::Main.up(&db, Some(1)).await?;
            db.execute_unprepared(&format!("CREATE TRIGGER fail_boundary BEFORE UPDATE ON bot_meta WHEN NEW.schema_version={failing_version} BEGIN SELECT RAISE(ABORT,'controlled boundary failure'); END")).await?;
            let error = initialize(&db, DatabaseOrigin::Existing).await.unwrap_err();
            let chain = format!("{error:#}");
            assert!(
                chain.contains(step) && chain.contains("controlled boundary failure"),
                "{chain}"
            );
            assert_eq!(names(&db, Migrator::Main).await?.len(), completed);
            assert_eq!(version(&db).await?, [6, 8, 9][completed - 1]);
            if failing_version == 9 {
                assert!(
                    !table_columns(&db, "thread_bindings")
                        .await?
                        .contains("target_json")
                );
            }
            if failing_version == 10 {
                publication::preflight_migration(&db).await?;
                assert!(
                    db.query_one_raw(statement(
                        "SELECT 1 FROM sqlite_schema WHERE name='bot_delivery_items_nine'",
                        vec![]
                    ))
                    .await?
                    .is_none()
                );
            }
            db.execute_unprepared("DROP TRIGGER fail_boundary").await?;
            initialize(&db, DatabaseOrigin::Existing).await?;
            let applied = names(&db, Migrator::Main).await?;
            assert_eq!(
                applied,
                [
                    lineage::LEDGER,
                    lineage::FILE8,
                    lineage::AUDIENCE9,
                    lineage::PUBLICATION10
                ]
            );
            assert_eq!(version(&db).await?, 10);
            // Reopening cannot replay even the published first step's metadata write.
            db.execute_unprepared("CREATE TRIGGER no_replay BEFORE UPDATE ON bot_meta BEGIN SELECT RAISE(ABORT,'completed step replayed'); END").await?;
            initialize(&db, DatabaseOrigin::Existing).await?;
            assert_eq!(names(&db, Migrator::Main).await?, applied);
        }
        Ok(())
    }

    #[tokio::test]
    async fn adopted_sources_keep_their_lineage_and_do_not_repeat_file6_repair()
    -> anyhow::Result<()> {
        for source in [
            Format::PreSix(3),
            Format::PreSix(5),
            Format::MainCard6,
            Format::File6,
            Format::File7,
            Format::File8,
            Format::Audience9,
            Format::Publication10,
        ] {
            let db = memory().await?;
            let prefix = match source {
                Format::PreSix(_) | Format::MainCard6 => 1,
                Format::Audience9 => 3,
                Format::Publication10 => 4,
                _ => 2,
            };
            Migrator::Main.up(&db, Some(1)).await?;
            let identity = inbound_identity("bot", "chat", "message");
            db.execute_raw(statement("INSERT INTO inbound_identities(identity,bot_id,message_id,chat_id,content_hash,admitted_at) VALUES(?,'bot','message','chat','input-hash',7)", vec![identity.clone().into()])).await?;
            db.execute_raw(statement("INSERT INTO inbound_work(identity,bot_id,chat_id,message_id,content_hash,text,chat_kind,app_id,project_id,creation_id,binding_revision,status,diagnostic,updated_at) VALUES(?,'bot','chat','message','input-hash','original question','group','app','project','creation',1,'pending','',7)", vec![identity.into()])).await?;
            db.execute_unprepared("INSERT INTO thread_bindings(chat_id,thread_id,status,creation_id,project_id,revision,generation,created_at) VALUES('chat','thread','bound','creation','project',1,1,7)").await?;
            if prefix > 1 {
                Migrator::Main.up(&db, Some(prefix - 1)).await?;
            }
            // Fixture boundary: these formats existed before any official tracking table.
            Migrator::Main.uninstall(&db).await?;
            if let Format::PreSix(version) = source {
                // Reconstruct the released text-only source, not just its numeric marker. Three
                // may lack these fields; five owns their complete known pre-file definitions.
                db.execute_unprepared("DROP TABLE bot_card_streams").await?;
                if version == 3 {
                    db.execute_unprepared("ALTER TABLE inbound_work DROP COLUMN attachments; ALTER TABLE inbound_work DROP COLUMN watch_input; ALTER TABLE inbound_work DROP COLUMN attempt_count; ALTER TABLE inbound_work DROP COLUMN next_attempt_at").await?;
                }
                db.execute_raw(statement(
                    "UPDATE bot_meta SET schema_version=? WHERE id=1",
                    vec![version.into()],
                ))
                .await?;
            }
            if matches!(source, Format::File6 | Format::File7) {
                db.execute_unprepared("DROP TABLE bot_card_streams").await?;
                db.execute_raw(statement(
                    "UPDATE bot_meta SET schema_version=? WHERE id=1",
                    vec![source.version().into()],
                ))
                .await?;
            }
            let text_source = matches!(source, Format::PreSix(_) | Format::MainCard6);
            let raw = if text_source {
                r#"[{"index":0,"uuid":"original-uuid","status":"succeeded","platform_message_id":"om-original","diagnostic":null}]"#
            } else {
                r#"[{"index":0,"uuid":"original-uuid","status":"rejected","platformMessageId":null,"diagnostic":"Feishu HTTP service is unavailable","upload":{"kind":"rejected"},"messageStage":"notStarted"}]"#
            };
            if text_source {
                db.execute_raw(statement("INSERT INTO send_operations(operation_id,bot_id,chat_id,content_hash,status,platform_message_ids,segment_facts,updated_at) VALUES('original','bot','chat','original-hash','succeeded','om-original',?,1)", vec![raw.into()])).await?;
            } else {
                db.execute_raw(statement("INSERT INTO send_operations(operation_id,bot_id,chat_id,content_hash,status,platform_message_ids,segment_facts,updated_at,send_identity,send_source) VALUES('original','bot','chat','original-hash','rejected','',?,1,'{\"kind\":\"file\",\"requestHash\":\"original-request\"}','null')", vec![raw.into()])).await?;
            }
            if matches!(source, Format::PreSix(_)) {
                // The no-facts row and the known partial row are independent historical facts.
                // Keep the exact original snake_case payload used by the pre3/pre5 root fixture.
                let known = r#"[{"index":0,"uuid":"old-uuid","status":"succeeded","platform_message_id":"pm-known","diagnostic":null},{"index":1,"uuid":"old-uuid-2","status":"rejected","platform_message_id":null,"diagnostic":"known rejection"}]"#;
                db.execute_raw(statement("INSERT INTO send_operations(operation_id,bot_id,chat_id,content_hash,status,platform_message_ids,segment_facts,updated_at) VALUES('op-with-facts','legacy','chat','old-text-hash','partial','pm-known',?,1)", vec![known.into()])).await?;
                db.execute_unprepared("INSERT INTO send_operations(operation_id,bot_id,chat_id,content_hash,status,platform_message_ids,updated_at) VALUES('op-without-facts','legacy','chat','hash','succeeded','pm-1',1)").await?;
            }
            initialize(&db, DatabaseOrigin::Existing).await?;
            let migrator = Migrator::for_source(source);
            let first = names(&db, migrator).await?;
            assert_eq!(first[0], source.adoption_name());
            let row = db
                .query_one_raw(statement(
                    "SELECT * FROM send_operations WHERE operation_id='original'",
                    vec![],
                ))
                .await?
                .unwrap();
            let record = send_record_from_row(row)?;
            assert_eq!(record.content_hash, "original-hash");
            assert_eq!(record.segments[0].uuid, "original-uuid");
            let scope = db.query_one_raw(statement("SELECT origin_json,needs_recovery FROM bot_delivery_scopes WHERE kind='legacyFinal'", vec![])).await?.unwrap();
            let origin: publication::DeliveryScopeOrigin =
                serde_json::from_str(&scope.try_get::<String>("", "origin_json")?)?;
            let publication::DeliveryScopeOrigin::LegacyFinal { legacy } = origin else {
                unreachable!()
            };
            assert_eq!(legacy.admission.as_ref().unwrap().admitted_at, 7);
            assert_eq!(
                legacy.admission.as_ref().unwrap().content_hash,
                "input-hash"
            );
            assert_eq!(scope.try_get::<i64>("", "needs_recovery")?, 0);
            assert_eq!(
                db.query_one_raw(statement("SELECT text FROM inbound_work", vec![]))
                    .await?
                    .unwrap()
                    .try_get::<String>("", "text")?,
                "original question"
            );
            match source {
                Format::PreSix(_) | Format::MainCard6 => {
                    assert_eq!(record.platform_message_ids, ["om-original"]);
                    assert_eq!(
                        record.segments[0].platform_message_id.as_deref(),
                        Some("om-original")
                    );
                }
                Format::File6 => assert_eq!(record.segments[0].upload, Some(UploadFact::Unknown)),
                _ => assert_eq!(record.segments[0].upload, Some(UploadFact::Rejected)),
            }
            let known_before = if matches!(source, Format::PreSix(_)) {
                let known = read_send(&db, "op-with-facts").await?;
                assert_eq!(known.identity, SendIdentity::LegacyText);
                assert_eq!(known.content_hash, "old-text-hash");
                assert_eq!(known.status, SendRecordStatus::Partial);
                assert!(known.facts_complete);
                assert_eq!(known.platform_message_ids, ["pm-known"]);
                assert_eq!(known.segments.len(), 2);
                assert_eq!(known.segments[0].uuid, "old-uuid");
                assert_eq!(
                    known.segments[0].platform_message_id.as_deref(),
                    Some("pm-known")
                );
                assert_eq!(
                    known.segments[0].message_stage,
                    Some(MessageStage::Accepted)
                );
                assert_eq!(known.segments[1].uuid, "old-uuid-2");
                assert_eq!(known.segments[1].status, SendRecordStatus::Rejected);
                assert_eq!(
                    known.segments[1].diagnostic.as_deref(),
                    Some("known rejection")
                );
                let missing = read_send(&db, "op-without-facts").await?;
                assert_eq!(missing.identity, SendIdentity::LegacyText);
                assert_eq!(missing.content_hash, "hash");
                assert_eq!(missing.platform_message_ids, ["pm-1"]);
                assert!(!missing.facts_complete);
                Some(known)
            } else {
                None
            };
            let before = serde_json::to_string(&record.segments)?;
            initialize(&db, DatabaseOrigin::Existing).await?;
            assert_eq!(names(&db, migrator).await?, first);
            assert_eq!(version(&db).await?, 10);
            let row = db
                .query_one_raw(statement(
                    "SELECT * FROM send_operations WHERE operation_id='original'",
                    vec![],
                ))
                .await?
                .unwrap();
            assert_eq!(
                serde_json::to_string(&send_record_from_row(row)?.segments)?,
                before
            );
            if let Some(before) = known_before {
                let after = read_send(&db, "op-with-facts").await?;
                assert_eq!(after.operation_id, before.operation_id);
                assert_eq!(after.identity, before.identity);
                assert_eq!(after.content_hash, before.content_hash);
                assert_eq!(after.status, before.status);
                assert_eq!(after.platform_message_ids, before.platform_message_ids);
                assert_eq!(after.segments, before.segments);
                assert_eq!(after.source, before.source);
                assert_eq!(after.facts_complete, before.facts_complete);
            }
        }
        Ok(())
    }

    async fn read_send(db: &DatabaseConnection, operation: &str) -> anyhow::Result<SendRecord> {
        let row = db.query_one_raw(statement("SELECT operation_id,bot_id,chat_id,content_hash,status,platform_message_ids,segment_facts,send_identity,send_source FROM send_operations WHERE operation_id=?", vec![operation.into()])).await?.ok_or_else(|| anyhow::anyhow!("known source send missing: {operation}"))?;
        Ok(send_record_from_row(row)?)
    }

    #[tokio::test]
    async fn readonly_preflight_rejects_incomplete_sources_and_mixed_or_gapped_records()
    -> anyhow::Result<()> {
        let empty = memory().await?;
        assert!(initialize(&empty, DatabaseOrigin::Existing).await.is_err());
        assert!(declarations(&empty).await?.is_empty());
        // Created 的空来源准入不能将 sqlitex_ 用户表误认为 sqlite_ 内部结构。
        // AUTOINCREMENT 同时产生真实 sqlite_sequence；两者的声明与原行都必须保留。
        let created = memory().await?;
        created
            .execute_unprepared(
                "CREATE TABLE sqlitex_unknown_authority (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                authority TEXT NOT NULL);
             INSERT INTO sqlitex_unknown_authority(authority) VALUES('original authority');",
            )
            .await?;
        let before = declarations(&created).await?;
        let completed = official_records(&created).await?;
        let original = created
            .query_all_raw(statement(
                "SELECT id,authority FROM sqlitex_unknown_authority ORDER BY id",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| {
                Ok((
                    row.try_get::<i64>("", "id")?,
                    row.try_get::<String>("", "authority")?,
                ))
            })
            .collect::<Result<Vec<_>, sea_orm::DbErr>>()?;
        let error = initialize(&created, DatabaseOrigin::Created)
            .await
            .unwrap_err();
        assert!(
            format!("{error:#}").contains("a newly owned bot ledger is not empty"),
            "{error:#}"
        );
        assert_eq!(declarations(&created).await?, before);
        assert_eq!(official_records(&created).await?, completed);
        let after = created
            .query_all_raw(statement(
                "SELECT id,authority FROM sqlitex_unknown_authority ORDER BY id",
                vec![],
            ))
            .await?
            .into_iter()
            .map(|row| {
                Ok((
                    row.try_get::<i64>("", "id")?,
                    row.try_get::<String>("", "authority")?,
                ))
            })
            .collect::<Result<Vec<_>, sea_orm::DbErr>>()?;
        assert_eq!(after, original);
        let sequence = created
            .query_one_raw(statement("SELECT name,seq FROM sqlite_sequence", vec![]))
            .await?
            .unwrap();
        assert_eq!(
            sequence.try_get::<String>("", "name")?,
            "sqlitex_unknown_authority"
        );
        assert_eq!(sequence.try_get::<i64>("", "seq")?, 1);
        for damage in [
            "unknown",
            "mixed",
            "gap",
            "missing-source",
            "partial-file",
            "contradictory-origin",
        ] {
            let db = memory().await?;
            Migrator::Main.up(&db, Some(2)).await?;
            match damage {
                "unknown" => {
                    db.execute_unprepared("UPDATE seaql_migrations SET version='unknown_future_step' WHERE version='m20261026_000001_bot_ledger_schema'").await?;
                }
                "mixed" => {
                    db.execute_unprepared("UPDATE seaql_migrations SET version='m20261026_000001_adopt_bot_publication10' WHERE version='m20261026_000001_bot_ledger_schema'").await?;
                }
                "gap" => {
                    db.execute_unprepared("DELETE FROM seaql_migrations WHERE version='m20261026_000001_bot_ledger_schema'").await?;
                }
                "missing-source" => {
                    Migrator::Main.uninstall(&db).await?;
                    db.execute_unprepared("DROP TABLE inbound_identities")
                        .await?;
                }
                "partial-file" => {
                    Migrator::Main.uninstall(&db).await?;
                    db.execute_unprepared("ALTER TABLE send_operations DROP COLUMN send_source")
                        .await?;
                }
                "contradictory-origin" => {
                    Migrator::Main.uninstall(&db).await?;
                    db.execute_unprepared("INSERT INTO thread_bindings(chat_id,thread_id,status,creation_id,project_id,revision,generation,created_at) VALUES('chat-a','thread','bound','creation','project',1,1,1),('chat-b','thread','bound','creation','project',1,1,1)").await?;
                }
                _ => unreachable!(),
            }
            let before = declarations(&db).await?;
            let completed = official_records(&db).await?;
            let format = version(&db).await?;
            assert!(
                initialize(&db, DatabaseOrigin::Existing).await.is_err(),
                "{damage}"
            );
            assert_eq!(declarations(&db).await?, before, "{damage}");
            assert_eq!(official_records(&db).await?, completed, "{damage}");
            assert_eq!(version(&db).await?, format, "{damage}");
        }
        for source in [Format::File6, Format::File7, Format::File8] {
            for table in ["inbound_work", "send_operations"] {
                let db = memory().await?;
                Migrator::Main.up(&db, Some(2)).await?;
                Migrator::Main.uninstall(&db).await?;
                if matches!(source, Format::File6 | Format::File7) {
                    db.execute_unprepared("DROP TABLE bot_card_streams").await?;
                    db.execute_raw(statement(
                        "UPDATE bot_meta SET schema_version=? WHERE id=1",
                        vec![source.version().into()],
                    ))
                    .await?;
                }
                // A type/default-compatible column is still an unknown persisted format. Keep it
                // in the source and require read-only rejection, never delete it to make import fit.
                db.execute_unprepared(&format!(
                    "ALTER TABLE {table} ADD COLUMN unexpected TEXT NOT NULL"
                ))
                .await?;
                let before = declarations(&db).await?;
                let completed = official_records(&db).await?;
                let format = version(&db).await?;
                assert!(
                    initialize(&db, DatabaseOrigin::Existing).await.is_err(),
                    "unknown column accepted in {source:?}/{table}"
                );
                assert_eq!(declarations(&db).await?, before, "{source:?}/{table}");
                assert_eq!(
                    official_records(&db).await?,
                    completed,
                    "{source:?}/{table}"
                );
                assert_eq!(version(&db).await?, format, "{source:?}/{table}");
            }
        }
        // 真实 Main -> Audience9 官方前缀和完整合法来源；不能让缺表夹具替空白 ID 制造假红灯。
        // 两份来源仅 platform_message_id 的值不同，合法对照必须实际完成 Publication10。
        for corrupt_message in [false, true] {
            use crate::bots::storage::card::{
                CardAction, CardBinding, CardLifecycle, CardOperation, CardOperationStatus,
                CardStream, hash,
            };
            let db = memory().await?;
            Migrator::Main.up(&db, Some(1)).await?;
            let identity = inbound_identity("bot", "chat", "message");
            let input = "bot:bot:chat:message";
            db.execute_raw(statement("INSERT INTO inbound_identities(identity,bot_id,message_id,chat_id,content_hash,admitted_at) VALUES(?,'bot','message','chat','input-hash',7)", vec![identity.clone().into()])).await?;
            db.execute_raw(statement("INSERT INTO inbound_work(identity,bot_id,chat_id,message_id,content_hash,text,chat_kind,app_id,project_id,creation_id,binding_revision,status,diagnostic,updated_at) VALUES(?,'bot','chat','message','input-hash','original question','group','app','project','creation',1,'pending','',7)", vec![identity.clone().into()])).await?;
            db.execute_unprepared("INSERT INTO thread_bindings(chat_id,thread_id,status,creation_id,project_id,revision,generation,created_at) VALUES('chat','thread','bound','creation','project',1,1,7)").await?;
            Migrator::Main.up(&db, Some(2)).await?;
            db.execute_raw(statement(
                "UPDATE inbound_work SET watch_input=? WHERE identity=?",
                vec![input.into(), identity.clone().into()],
            ))
            .await?;
            let action = CardAction::Settings {
                streaming: false,
                lifecycle: CardLifecycle::Cancelled,
                recovery: false,
            };
            let mut stream = CardStream {
                binding: CardBinding {
                    bot_id: "bot".into(),
                    chat_id: "chat".into(),
                    message_id: "message".into(),
                    thread_id: "thread".into(),
                    original_input: input.into(),
                },
                watch_input: input.into(),
                turn_id: Some("original-turn".into()),
                version: 1,
                lifecycle: CardLifecycle::Cancelled,
                card_id: Some(" \tcard-original\u{2003}".into()),
                platform_message_id: Some(format!("\t{}\u{2003}", "om".repeat(160))),
                sequence: 1,
                confirmed_sequence: 1,
                confirmed_text: "original preview".into(),
                confirmed_content_hash: hash(b"original preview"),
                final_content_hash: None,
                last_operation: Some(CardOperation {
                    content_hash: hash(&serde_json::to_vec(&action)?),
                    action,
                    sequence: 1,
                    uuid: "0123456789abcdef0123456789abcdef".into(),
                    status: CardOperationStatus::Confirmed,
                    diagnostic: None,
                }),
                recovery_used: false,
                recovery: None,
                diagnostic: None,
            };
            let valid_raw = serde_json::to_string(&stream)?;
            db.execute_raw(statement("INSERT INTO bot_card_streams(identity,bot_id,chat_id,message_id,thread_id,original_input,watch_input,turn_id,version,state_json,updated_at) VALUES(?,'bot','chat','message','thread',?,?,'original-turn',1,?,7)", vec![identity.clone().into(), input.into(), input.into(), valid_raw.clone().into()])).await?;
            preflight::inspect(&db, DatabaseOrigin::Existing).await?;
            assert_eq!(
                names(&db, Migrator::Main).await?,
                [lineage::LEDGER, lineage::FILE8, lineage::AUDIENCE9]
            );
            if corrupt_message {
                stream.platform_message_id = Some(" \t\r\n\u{2003}".into());
                let damaged_raw = serde_json::to_string(&stream)?;
                db.execute_raw(statement(
                    "UPDATE bot_card_streams SET state_json=? WHERE identity=?",
                    vec![damaged_raw.clone().into(), identity.clone().into()],
                ))
                .await?;
                let schema_before = declarations(&db).await?;
                let completed = official_records(&db).await?;
                let error = Migrator::Main.up(&db, None).await.unwrap_err();
                assert!(
                    format!("{error:#}").contains("card stream state is unreadable"),
                    "{error:#}"
                );
                assert!(initialize(&db, DatabaseOrigin::Existing).await.is_err());
                assert_eq!(declarations(&db).await?, schema_before);
                assert_eq!(official_records(&db).await?, completed);
                assert_eq!(version(&db).await?, 9);
                let row = db.query_one_raw(statement("SELECT state_json,version,updated_at FROM bot_card_streams WHERE identity=?", vec![identity.into()])).await?.unwrap();
                assert_eq!(row.try_get::<String>("", "state_json")?, damaged_raw);
                assert_eq!(row.try_get::<i64>("", "version")?, 1);
                assert_eq!(row.try_get::<i64>("", "updated_at")?, 7);
            } else {
                initialize(&db, DatabaseOrigin::Existing).await?;
                assert_eq!(version(&db).await?, 10);
                assert_eq!(
                    names(&db, Migrator::Main).await?,
                    [
                        lineage::LEDGER,
                        lineage::FILE8,
                        lineage::AUDIENCE9,
                        lineage::PUBLICATION10
                    ]
                );
                let row = db
                    .query_one_raw(statement(
                        "SELECT state_json FROM bot_delivery_items WHERE kind='legacyFinal'",
                        vec![],
                    ))
                    .await?
                    .unwrap();
                let state: publication::DeliveryEntityState =
                    serde_json::from_str(&row.try_get::<String>("", "state_json")?)?;
                assert_eq!(state.card.card_id, stream.card_id);
                assert_eq!(state.card.platform_message_id, stream.platform_message_id);
                let settled = state.settled.unwrap();
                assert_eq!(settled.intent.uuid, stream.last_operation.unwrap().uuid);
                assert_eq!(settled.intent.sequence, 1);
                assert!(
                    matches!(settled.result, publication::DeliveryResult::SettingsAccepted { card_id, streaming: false } if Some(card_id.as_str()) == stream.card_id.as_deref())
                );
                publication::validate_schema(&db).await?;
                initialize(&db, DatabaseOrigin::Existing).await?;
            }
        }
        Ok(())
    }
}

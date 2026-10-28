//! The current history format has one official lineage, independent of the retained v2 codec.

use super::*;
use sea_orm_migration::{DbErr, MigrationName, MigrationTrait, MigratorTraitSelf, SchemaManager};

pub(super) const CURRENT_STEP: &str = "m20261026_100001_history_current";

#[cfg(test)]
#[derive(Clone, Copy)]
#[repr(u8)]
pub(in crate::studio::storage) enum MigrationFault {
    EnvelopeUpdate = 1,
    ModelAccessUpdate = 2,
    IdentityUpdate = 3,
    ToolAnswerUpdate = 4,
    LegacyInsert = 5,
}

#[cfg(test)]
impl HistoryStore {
    /// Private storage fault point: rejects a real target mutation in the official transaction.
    pub(in crate::studio::storage) fn set_migration_fault(&self, fault: Option<MigrationFault>) {
        self.state.migration_fault.store(
            fault.map_or(0, |fault| fault as u8),
            std::sync::atomic::Ordering::Release,
        );
    }
}

#[cfg(test)]
pub(super) async fn inject_fault(
    db: &impl ConnectionTrait,
    control: &std::sync::atomic::AtomicU8,
    stage: MigrationFault,
) -> Result<()> {
    if control.load(std::sync::atomic::Ordering::Acquire) != stage as u8 {
        return Ok(());
    }
    let mutation = match stage {
        MigrationFault::ToolAnswerUpdate => "BEFORE UPDATE OF payload ON history_items",
        MigrationFault::LegacyInsert => "BEFORE INSERT ON session_checkpoint",
        _ => "BEFORE UPDATE OF payload ON session_checkpoint",
    };
    db.execute_unprepared(&format!(
        "CREATE TEMP TRIGGER reject_current_migration {mutation} BEGIN SELECT RAISE(ABORT,'injected target history migration write failure'); END;"
    )).await?;
    Ok(())
}

#[cfg(test)]
pub(super) async fn clear_fault(
    db: &impl ConnectionTrait,
    control: &std::sync::atomic::AtomicU8,
    stage: MigrationFault,
) -> Result<()> {
    if control.load(std::sync::atomic::Ordering::Acquire) == stage as u8 {
        db.execute_unprepared("DROP TRIGGER IF EXISTS temp.reject_current_migration")
            .await?;
    }
    Ok(())
}

struct CurrentMigrator {
    thread_id: String,
    origin: Option<HistoryInitialization>,
    failure: std::sync::Arc<std::sync::Mutex<Option<anyhow::Error>>>,
    #[cfg(test)]
    fault: std::sync::Arc<std::sync::atomic::AtomicU8>,
}

impl MigratorTraitSelf for CurrentMigrator {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        vec![Box::new(CurrentHistory {
            thread_id: self.thread_id.clone(),
            origin: self.origin.clone(),
            failure: self.failure.clone(),
            #[cfg(test)]
            fault: self.fault.clone(),
        })]
    }
}

struct CurrentHistory {
    thread_id: String,
    origin: Option<HistoryInitialization>,
    failure: std::sync::Arc<std::sync::Mutex<Option<anyhow::Error>>>,
    #[cfg(test)]
    fault: std::sync::Arc<std::sync::atomic::AtomicU8>,
}

impl MigrationName for CurrentHistory {
    fn name(&self) -> &str {
        CURRENT_STEP
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CurrentHistory {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> std::result::Result<(), DbErr> {
        let db = manager.get_connection();
        let origin = self.origin.as_ref().ok_or_else(|| {
            DbErr::Migration("current history initialization requires an explicit origin".into())
        })?;
        // This step runs in SeaORM's target transaction. It never begins a second target tx, and
        // the framework completion row is committed with the structure, imported facts and checks.
        db.execute_unprepared(schema::SCHEMA_DDL).await?;
        match origin {
            HistoryInitialization::New => {
                db.execute_raw(statement(
                    "INSERT INTO history_meta(id,schema_version,database_id,thread_id,applied_write_seq) VALUES(1,?,?,?,0)",
                    vec![HISTORY_SCHEMA_VERSION.into(), crate::studio::new_id("history-db").into(), self.thread_id.clone().into()],
                )).await?;
            }
            HistoryInitialization::ImportV2 {
                source_database,
                legacy_state,
                migrate_execution_identity,
            } => {
                import::from_v2(
                    db,
                    &self.thread_id,
                    source_database,
                    legacy_state,
                    migrate_execution_identity,
                    #[cfg(test)]
                    &self.fault,
                )
                .await
                .map_err(|error| self.conversion(error))?;
            }
        }
        schema::verify_structure(db).await?;
        schema::verify_target_migration_uniqueness(db).await?;
        validation::contents(db, &self.thread_id)
            .await
            .map_err(|error| self.conversion(error))?;
        Ok(())
    }
}

pub(super) async fn initialize(
    db: &DatabaseConnection,
    thread_id: &str,
    origin: HistoryInitialization,
    #[cfg(test)] fault: std::sync::Arc<std::sync::atomic::AtomicU8>,
) -> Result<()> {
    let migrator = CurrentMigrator {
        thread_id: thread_id.into(),
        origin: Some(origin),
        failure: Default::default(),
        #[cfg(test)]
        fault,
    };
    let applied = migrator.get_applied_migrations_read_only(db).await?;
    if !applied.is_empty() {
        validate_ready(db, thread_id).await?;
        return Ok(());
    }
    ensure!(db.query_one_raw(statement(
        "SELECT name FROM sqlite_schema WHERE type='table' AND name NOT GLOB 'sqlite_*' AND name<>'seaql_migrations' LIMIT 1", vec![]
    )).await?.is_none(), "unfinished preparation contains unproven tables; existing data preserved");
    if let Err(error) = migrator.up(db, None).await {
        let original = migrator
            .failure
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
        let error = match original {
            Some(original) => original.context(error),
            None => error.into(),
        };
        return Err(crate::studio::startup::migration_error(
            "history-current",
            CURRENT_STEP,
            error,
        ));
    }
    validate_ready(db, thread_id).await?;
    Ok(())
}

pub(super) async fn verify_completion(db: &impl ConnectionTrait) -> Result<()> {
    // Bound the official ledger before asking the framework to classify it. A current target has
    // one registered step; a forged, arbitrarily large ledger is not unbounded proof work.
    let recorded = db
        .query_all_raw(statement(
            "SELECT (typeof(version)='text' AND version=? COLLATE BINARY) AS known_step FROM seaql_migrations LIMIT 2",
            vec![CURRENT_STEP.into()],
        ))
        .await?;
    ensure!(
        recorded.len() == 1 && recorded[0].try_get::<i64>("", "known_step")? == 1,
        "current history has no complete official lineage; existing data preserved"
    );
    schema::verify_target_migration_uniqueness(db).await?;
    let migrator = CurrentMigrator {
        thread_id: String::new(),
        origin: None,
        failure: Default::default(),
        #[cfg(test)]
        fault: Default::default(),
    };
    let applied = migrator.get_applied_migrations_read_only(db).await?;
    ensure!(
        applied.len() == 1 && applied[0].name() == CURRENT_STEP,
        "current history has no complete official lineage; existing data preserved"
    );
    ensure!(
        migrator
            .get_pending_migrations_read_only(db)
            .await?
            .is_empty(),
        "current history has pending migrations"
    );
    Ok(())
}

pub(super) async fn validate_ready(
    db: &impl ConnectionTrait,
    thread_id: &str,
) -> Result<(String, i64)> {
    let identity = validate_readable(db, thread_id).await?;
    validation::contents(db, thread_id).await?;
    Ok(identity)
}

pub(super) async fn validate_readable(
    db: &impl ConnectionTrait,
    thread_id: &str,
) -> Result<(String, i64)> {
    let identity = validate_existing(db, thread_id).await?;
    schema::verify_structure(db).await?;
    schema::verify_authoritative_objects(db).await?;
    Ok(identity)
}

pub(super) async fn inspect_ready(path: &Path, thread_id: &str) -> Result<(String, i64)> {
    let db = connect_read_only(path).await?;
    let tx = db.begin().await?;
    let result = validate_ready(&tx, thread_id).await;
    let ended = tx.rollback().await;
    let closed = db.close().await;
    // Always release the read snapshot and the pool before returning, including validation errors.
    let identity = result?;
    ended?;
    closed?;
    Ok(identity)
}

impl CurrentHistory {
    fn conversion(&self, error: anyhow::Error) -> DbErr {
        match error.downcast::<DbErr>() {
            Ok(error) => error,
            Err(error) => {
                let diagnostic = format!("{error:#}");
                *self
                    .failure
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(error);
                DbErr::Migration(diagnostic)
            }
        }
    }
}

#[cfg(test)]
mod import_tests {
    use super::*;
    use pl_core::{
        context::{
            ContextContent, ContextRecord, ContextSnapshot, ContextSource, OpaquePayload,
            content_hash,
        },
        thread::{ThreadCheckpoint, ThreadEffectBatch, ThreadSnapshot},
    };
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    };

    async fn seeded_source(path: &Path, thread_id: &str) -> Result<HistoryStore> {
        let history = HistoryStore::open(path, thread_id).await?;
        history.initialize(HistoryInitialization::New).await?;
        // Preserve the fixture's real watermark7 while exercising the production contiguous-save
        // contract: the preceding empty commits are real writer transactions, not a forged fence.
        for sequence in 1..7 {
            history.commit(sequence, &[], &[]).await?;
        }
        let mut state = ThreadSnapshot {
            commit_sequence: 7,
            context: ContextSnapshot {
                revision: 1,
                records: vec![ContextRecord {
                    id: "context-1".into(),
                    turn_id: None,
                    source: ContextSource::User,
                    content: vec![ContextContent::Text {
                        text: "源快照与 WAL 的完整正文".into(),
                    }],
                    tool_calls: vec![],
                }]
                .into(),
            },
            ..Default::default()
        };
        state
            .usage_summary
            .estimated_costs
            .push(pl_core::thread::UsageCost {
                currency: "USD".into(),
                amount: 3.5,
            });
        let mut message = ThreadItem::completed_user_message(
            "input-1".into(),
            thread_id.into(),
            "turn-1".into(),
            "必须完整保留的输入".into(),
            vec![],
            11,
        );
        message.ordinal = 1;
        message.revision = 1;
        let turn = ThreadItem::new(
            "turn:turn-1".into(),
            thread_id.into(),
            "turn-1".into(),
            2,
            1,
            11,
            11,
            ThreadItemState::Turn(pl_protocol::ThreadTurnItem::new(
                pl_protocol::TurnState::Completed(pl_protocol::CompletedTurnState::new(
                    Some(11),
                    11,
                    pl_protocol::TurnCompletion::Normal,
                )),
            )),
        );
        let input = InputIdentityWrite {
            entry: super::super::super::state::InputIdentityEntry {
                id: "input-1".into(),
                digest: content_hash(b"original-input"),
                continuation: None,
                delivery: Default::default(),
                purpose: Default::default(),
                expected_model_route_revision: None,
                continuation_admission_revision: None,
                ordinal: 1,
                revision: 1,
                accepted_sequence: 7,
                state: pl_core::thread::input::InputState::Consumed {
                    turn_id: "turn-1".into(),
                    attempt_id: "attempt-1".into(),
                },
            },
            request_digest: Some(content_hash(b"original-host-request")),
            presentation: pl_protocol::MessagePresentation::Visible,
        };
        let messages = [MessageIdentityWrite {
            message_id: "message-1".into(),
            item_id: "input-1".into(),
            sequence: 7,
            digest: Some(content_hash(b"original-message")),
        }];
        let task = pl_core::thread::task::TaskRecord {
            id: "task:call-1".into(),
            call_id: "call-1".into(),
            tool_id: "fixture".into(),
            turn_id: "turn-1".into(),
            revision: 1,
            status: pl_core::thread::task::TaskStatus::Succeeded,
            cancel_requested: false,
            acknowledgement: None,
            started_sequence: Some(7),
        };
        let delivery = pl_core::thread::ToolDelivery {
            target: Default::default(),
            call_id: task.call_id.clone(),
            tool_id: task.tool_id.clone(),
            output: pl_core::tool::ToolOutput::new(
                OpaquePayload::new("fixture.unknown", 17, "未识别的原始供应商结果")?,
                vec![],
            ),
            delivered_context: vec![],
            outcome: pl_core::thread::ToolOutcome::Succeeded,
        };
        let payload = "{\"futurePayload\": { \"number\": 1e+00, \"text\": \"原始回执\" }}";
        let receipts = [FactReceiptWrite {
            item_id: crate::studio::thread_projection::order::receipt_id(
                "permission",
                "permission-1",
            ),
            revision: 1,
            kind: "permission",
            payload: payload.into(),
        }];
        let checkpoint = ThreadCheckpoint::capture(thread_id.into(), 7, state);
        history
            .commit_checkpoint_effect(
                &checkpoint,
                &ThreadEffectBatch {
                    thread_id: thread_id.into(),
                    sequence: 7,
                    context: Some(pl_core::thread::journal::ContextChange::Append {
                        revision: checkpoint.state.context.revision,
                        records: checkpoint.state.context.records.clone(),
                    }),
                    ..Default::default()
                },
                EffectCommit {
                    items: &[message, turn],
                    rolled_back_turns: &Default::default(),
                    identities: &[input],
                    messages: &messages,
                    receipts: &receipts,
                    tasks: &[task],
                    deliveries: &[delivery],
                    delivery_repairs: &[],
                    attempt: None,
                },
            )
            .await?;
        let db = &history.writer().await?.db;
        db.execute_unprepared(
            "INSERT INTO session_costs(purpose,currency,amount) VALUES('null','USD',3.5)",
        )
        .await?;
        // The source fixture represents the published pre-official v2 format. Its subsequent
        // official completion rows are produced by the *real* released migration objects below,
        // never inserted by hand. It is a separate source file, never renamed to become a target.
        db.execute_unprepared(
            "DROP TABLE seaql_migrations; UPDATE history_meta SET schema_version=8",
        )
        .await?;
        super::super::schema::advance_released_eight(db, thread_id, None).await?;
        let original = checkpoint::read(db, thread_id)
            .await?
            .context("source checkpoint")?;
        super::super::schema::advance_released_eight(
            db,
            thread_id,
            Some((original.clone(), original)),
        )
        .await?;
        // Unknown JSON fields and their original encoding must survive in every opaque row.
        for (table, column, key) in [
            ("history_items", "payload", "ordinal=1"),
            ("session_checkpoint", "payload", "id=1"),
            ("current_context", "payload", "ordinal=0"),
            ("history_tool_tasks", "task_payload", "call_id='call-1'"),
        ] {
            let row = db
                .query_one_raw(statement(
                    &format!("SELECT {column} AS payload FROM {table} WHERE {key}"),
                    vec![],
                ))
                .await?
                .context("fixture row")?;
            let raw: String = row.try_get("", "payload")?;
            let augmented = raw_json::replace_encoded(
                &raw,
                &["vendorFuture"],
                "{ \"number\" : 1e+00, \"unknown\" : [1, 2] }",
            )?;
            if matches!(table, "session_checkpoint" | "current_context") {
                db.execute_raw(statement(
                    &format!("UPDATE {table} SET {column}=?,payload_hash=? WHERE {key}"),
                    vec![
                        augmented.clone().into(),
                        content_hash(augmented.as_bytes()).into(),
                    ],
                ))
                .await?;
            } else {
                db.execute_raw(statement(
                    &format!("UPDATE {table} SET {column}=? WHERE {key}"),
                    vec![augmented.into()],
                ))
                .await?;
            }
        }
        db.execute_unprepared("PRAGMA wal_autocheckpoint=0").await?;
        Ok(history)
    }

    fn origin(
        source: &Path,
        thread_id: &str,
        migration: initialization::ExecutionIdentityMigration,
    ) -> HistoryInitialization {
        HistoryInitialization::ImportV2 {
            source_database: source.into(),
            legacy_state: super::super::super::state::StateStore::new(
                source.parent().unwrap().into(),
                thread_id,
            ),
            migrate_execution_identity: migration,
        }
    }

    async fn raw_rows(db: &impl ConnectionTrait, table: &str) -> Result<Vec<(i64, String)>> {
        let mut result = Vec::new();
        let mut cursor = None;
        while let Some(row) = import::next_row(db, table, cursor).await? {
            let rowid = row.try_get("", "__source_rowid")?;
            // This test fixture is small. Every column, including NULLs and raw payload text,
            // participates in its independent comparison, not just row counts.
            let mut values = Vec::new();
            for (column, kind) in schema::columns(table) {
                let value = match kind {
                    "INTEGER" => serde_json::to_value(row.try_get::<Option<i64>>("", column)?)?,
                    "REAL" => serde_json::to_value(row.try_get::<Option<f64>>("", column)?)?,
                    "TEXT" => serde_json::to_value(row.try_get::<Option<String>>("", column)?)?,
                    _ => unreachable!(),
                };
                values.push((column, value));
            }
            result.push((rowid, serde_json::to_string(&values)?));
            cursor = Some(rowid);
        }
        Ok(result)
    }

    enum MetaColumnFixture {
        Ordinary,
        ExtraStored,
        VirtualFence,
        StoredFence,
    }

    /// Rebuilds only the fixture's one-row metadata table. STORED cannot be added with ALTER;
    /// the four nongenerated identity fields and the original rowid/format remain unchanged.
    fn rebuild_meta_columns(shape: MetaColumnFixture) -> String {
        let ordinary = "id,schema_version,database_id,thread_id,applied_write_seq";
        let generated = "id,schema_version,database_id,thread_id";
        let (fence, extra, copied) = match shape {
            MetaColumnFixture::Ordinary => ("INTEGER NOT NULL", "", ordinary),
            MetaColumnFixture::ExtraStored => (
                "INTEGER NOT NULL",
                ",future_col TEXT GENERATED ALWAYS AS (thread_id) STORED",
                ordinary,
            ),
            // Both real import fixtures already have fence7. Keep every value unchanged while
            // replacing the required physical column with an identically typed generated column.
            MetaColumnFixture::VirtualFence => (
                "INTEGER NOT NULL GENERATED ALWAYS AS (7) VIRTUAL",
                "",
                generated,
            ),
            MetaColumnFixture::StoredFence => (
                "INTEGER NOT NULL GENERATED ALWAYS AS (7) STORED",
                "",
                generated,
            ),
        };
        format!(
            "ALTER TABLE history_meta RENAME TO retained_meta_fixture;
             CREATE TABLE history_meta (
                id INTEGER PRIMARY KEY CHECK (id=1), schema_version INTEGER NOT NULL,
                database_id TEXT NOT NULL, thread_id TEXT NOT NULL,
                applied_write_seq {fence}{extra});
             INSERT INTO history_meta({copied}) SELECT {copied} FROM retained_meta_fixture;
             DROP TABLE retained_meta_fixture;"
        )
    }

    async fn retry_fixture(
        directory: &Path,
        coordinator: &super::super::super::coordinator::ThreadPersistenceCoordinator,
        thread: &str,
        reject: Arc<std::sync::atomic::AtomicBool>,
        calls: Arc<AtomicUsize>,
    ) -> Result<(HistoryStore, HistoryStore, PathBuf)> {
        let source_path = directory.join(format!("source-{thread}.sqlite"));
        let source = seeded_source(&source_path, thread).await?;
        source.writer().await?.db.execute_unprepared(
            "DELETE FROM seaql_migrations WHERE version='m20261026_000008_history_execution_identity'"
        ).await?;
        let raw =
            HistoryStore::open(&directory.join(format!("current-{thread}.sqlite")), thread).await?;
        let target = coordinator.install_shared_history(thread, &raw);
        let initial = target
            .initialize(origin(
                &source_path,
                thread,
                Arc::new(move |_| {
                    calls.fetch_add(1, Ordering::SeqCst);
                    if reject.load(Ordering::SeqCst) {
                        return Err(std::io::Error::new(
                            std::io::ErrorKind::PermissionDenied,
                            "injected explicit history retry failure",
                        )
                        .into());
                    }
                    Ok(())
                }),
            ))
            .await;
        assert!(
            initial.is_err(),
            "fixture must expose an observed Failed job"
        );
        Ok((source, target, source_path))
    }

    #[tokio::test]
    async fn explicit_registry_retry_continues_after_failures_and_retains_original_sources()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let coordinator = super::super::super::coordinator::ThreadPersistenceCoordinator::default();
        let mut fixtures = Vec::new();
        for thread in ["a-failed", "b-recovered", "c-failed"] {
            let reject = Arc::new(std::sync::atomic::AtomicBool::new(true));
            let calls = Arc::new(AtomicUsize::new(0));
            let (source, target, path) = retry_fixture(
                directory.path(),
                &coordinator,
                thread,
                reject.clone(),
                calls.clone(),
            )
            .await?;
            let evidence = super::super::test_support::source_evidence(&path).await?;
            if thread == "b-recovered" {
                reject.store(false, Ordering::SeqCst);
            }
            fixtures.push((thread, source, target, path, calls, evidence));
        }
        let inactive =
            HistoryStore::open(&directory.path().join("inactive.sqlite"), "inactive").await?;
        coordinator.install_shared_history("inactive", &inactive);
        let ready_path = directory.path().join("ready.sqlite");
        let ready = coordinator
            .install_shared_history("ready", &HistoryStore::open(&ready_path, "ready").await?);
        ready.initialize(HistoryInitialization::New).await?;
        assert!(ready.checkpoint().await?.is_none());
        let ready_before = super::super::test_support::source_evidence(&ready_path).await?;
        let failure = coordinator
            .retry_history_initializations()
            .await
            .expect_err(
                "all remaining failure sources must be reported after trying the recoverable owner",
            );
        assert!(
            failure.to_string().contains("a-failed") && failure.to_string().contains("c-failed")
        );
        assert!(
            !failure.to_string().contains("inactive") && !failure.to_string().contains("ready")
        );
        assert!(
            failure
                .chain()
                .any(|cause| cause.downcast_ref::<std::io::Error>().is_some()),
            "aggregation preserves the original typed I/O source, not only rendered text"
        );
        for (thread, _source, target, path, calls, evidence) in &fixtures {
            assert_eq!(
                calls.load(Ordering::SeqCst),
                2,
                "one explicit attempt per Failed owner: {thread}"
            );
            let same = coordinator
                .shared_history(thread)
                .context("same registered retry owner")?;
            assert!(Arc::ptr_eq(&same.state, &target.state));
            if *thread == "b-recovered" {
                assert_eq!(same.watermark().await?, 7);
            } else {
                assert!(same.checkpoint().await.is_err());
            }
            assert_eq!(
                super::super::test_support::source_evidence(path).await?,
                *evidence
            );
        }
        assert!(!directory.path().join("inactive.sqlite").exists());
        assert_eq!(
            super::super::test_support::source_evidence(&ready_path).await?,
            ready_before
        );
        Ok(())
    }

    #[tokio::test]
    async fn cancelled_explicit_registry_retry_is_retained_until_drain() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let coordinator = super::super::super::coordinator::ThreadPersistenceCoordinator::default();
        let reject = Arc::new(std::sync::atomic::AtomicBool::new(true));
        let calls = Arc::new(AtomicUsize::new(0));
        let (_source, target, source_path) = retry_fixture(
            directory.path(),
            &coordinator,
            "retry-cancel",
            reject.clone(),
            calls.clone(),
        )
        .await?;
        let original = super::super::test_support::source_evidence(&source_path).await?;
        reject.store(false, Ordering::SeqCst);
        let share = target.shared();
        let (entered, release) = target.arm_init_gate().await;
        let waiting = coordinator.clone();
        let waiter = tokio::spawn(async move { waiting.retry_history_initializations().await });
        entered.await?;
        waiter.abort();
        assert!(waiter.await.unwrap_err().is_cancelled());
        drop(target);
        let same = coordinator
            .shared_history("retry-cancel")
            .context("registry retains cancelled retry")?;
        assert!(HistoryStore::from_share(&share).is_some());
        // The replacement worker is in flight, not a new confirmed failure to restart.
        let in_flight_retry = coordinator.retry_history_initializations().await;
        release
            .send(())
            .map_err(|_| anyhow::anyhow!("retry worker disappeared"))?;
        let drained = coordinator.drain_history_preparations().await;
        in_flight_retry?;
        drained?;
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        assert_eq!(same.watermark().await?, 7);
        assert_eq!(
            super::super::test_support::source_evidence(&source_path).await?,
            original
        );
        drop(same);
        assert!(
            HistoryStore::from_share(&share).is_none(),
            "successful retry releases its temporary strong pin"
        );
        Ok(())
    }

    #[tokio::test]
    async fn current_new_is_explicit_and_cold_reads_never_create_or_adopt_files() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory
            .path()
            .join("unmaterialized/history-current.sqlite");
        let cold = HistoryStore::open(&path, "new").await?;
        assert!(cold.checkpoint().await.is_err());
        assert!(!path.parent().unwrap().exists());
        assert!(cold.prepare_activation().await.is_err());
        assert!(!path.exists());
        cold.initialize(HistoryInitialization::New).await?;
        assert!(cold.checkpoint().await?.is_none());
        assert_eq!(cold.watermark().await?, 0);
        let ready = HistoryStore::open(&path, "new").await?;
        ready.initialize(HistoryInitialization::New).await?;
        assert_eq!(ready.watermark().await?, 0);
        #[cfg(unix)]
        {
            let original = tokio::fs::read(&path).await?;
            let alias = directory.path().join("hard-linked-current.sqlite");
            tokio::fs::hard_link(&path, &alias).await?;
            let linked = HistoryStore::open(&path, "new").await?;
            let failure = linked.checkpoint().await.unwrap_err();
            assert!(
                format!("{failure:#}").contains("invalid hard-link count 2"),
                "{failure:#}"
            );
            assert!(linked.initialize(HistoryInitialization::New).await.is_err());
            assert_eq!(tokio::fs::read(&path).await?, original);
            assert_eq!(tokio::fs::read(&alias).await?, original);
            tokio::fs::remove_file(&alias).await?;
            assert!(
                HistoryStore::open(&path, "new")
                    .await?
                    .checkpoint()
                    .await?
                    .is_none()
            );
        }
        assert!(
            HistoryStore::open(&path, "foreign")
                .await?
                .initialize(HistoryInitialization::New)
                .await
                .is_err()
        );
        let empty = directory.path().join("unknown.sqlite");
        tokio::fs::File::create(&empty).await?;
        assert!(
            HistoryStore::open(&empty, "new")
                .await?
                .initialize(HistoryInitialization::New)
                .await
                .is_err()
        );
        assert_eq!(tokio::fs::metadata(empty).await?.len(), 0);
        Ok(())
    }

    #[tokio::test]
    async fn complete_v2_wal_snapshot_preserves_all_ten_tables_and_unknown_payloads() -> Result<()>
    {
        let directory = tempfile::tempdir()?;
        let source_path = directory.path().join("history.sqlite");
        let target_path = directory.path().join("history-current.sqlite");
        let source = seeded_source(&source_path, "retained").await?;
        let source_db = &source.writer().await?.db;
        let source_bytes = tokio::fs::read(&source_path).await?;
        let wal_path = source_path.with_file_name("history.sqlite-wal");
        let wal_bytes = tokio::fs::read(&wal_path).await?;
        assert!(
            !wal_bytes.is_empty(),
            "fixture must contain a real committed WAL"
        );
        let target = HistoryStore::open(&target_path, "retained").await?;
        target
            .initialize(origin(
                &source_path,
                "retained",
                Arc::new(|_| anyhow::bail!("completed old m8 must not run again")),
            ))
            .await?;
        let db = &target.writer().await?.db;
        for table in schema::tables().filter(|table| *table != "history_meta") {
            assert_eq!(
                raw_rows(db, table).await?,
                raw_rows(source_db, table).await?,
                "{table}"
            );
        }
        let id = |row: sea_orm::QueryResult| -> Result<(String, String, i64)> {
            Ok((
                row.try_get("", "database_id")?,
                row.try_get("", "thread_id")?,
                row.try_get("", "applied_write_seq")?,
            ))
        };
        assert_eq!(
            id(db
                .query_one_raw(statement("SELECT * FROM history_meta WHERE id=1", vec![]))
                .await?
                .unwrap())?,
            id(source_db
                .query_one_raw(statement("SELECT * FROM history_meta WHERE id=1", vec![]))
                .await?
                .unwrap())?
        );
        assert_eq!(tokio::fs::read(&source_path).await?, source_bytes);
        assert_eq!(tokio::fs::read(&wal_path).await?, wal_bytes);
        let checkpoint = target.checkpoint().await?.context("imported checkpoint")?;
        assert_eq!(checkpoint.history_fence, 7);
        let after = ThreadCheckpoint::capture(
            "retained".into(),
            8,
            ThreadSnapshot {
                commit_sequence: 8,
                ..checkpoint.state.clone()
            },
        );
        target
            .commit_checkpoint_effect(
                &after,
                &ThreadEffectBatch {
                    thread_id: "retained".into(),
                    sequence: 8,
                    ..Default::default()
                },
                EffectCommit {
                    items: &[],
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
        assert_eq!(
            applied_write_seq(source_db).await?,
            7,
            "normal writes must not dual-write the source"
        );
        let cold = HistoryStore::open(&target_path, "retained").await?;
        assert_eq!(
            cold.checkpoint()
                .await?
                .context("cold restore")?
                .history_fence,
            8
        );
        // After publication the source is not consulted, even if it later becomes unavailable.
        let reopened = HistoryStore::open(&target_path, "retained").await?;
        reopened
            .initialize(origin(
                &directory.path().join("absent.sqlite"),
                "retained",
                Arc::new(|_| panic!("must not import twice")),
            ))
            .await?;
        assert_eq!(reopened.watermark().await?, 8);
        verify_completion(db).await?;
        Ok(())
    }

    #[tokio::test]
    async fn failed_import_rolls_back_the_official_step_and_retains_source_then_explicitly_retries()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let source_path = directory.path().join("history.sqlite");
        let target_path = directory.path().join("history-current.sqlite");
        let source = seeded_source(&source_path, "retry").await?;
        let db = &source.writer().await?.db;
        // A legitimate pending old identity step. Only the test's corruption/fixture boundary
        // changes the ledger; production never inserts or removes official completion rows.
        db.execute_unprepared("DELETE FROM seaql_migrations WHERE version='m20261026_000008_history_execution_identity'").await?;
        let calls = Arc::new(AtomicUsize::new(0));
        let invoked = calls.clone();
        let target = HistoryStore::open(&target_path, "retry").await?;
        let init = origin(
            &source_path,
            "retry",
            Arc::new(move |state| {
                if invoked.fetch_add(1, Ordering::SeqCst) == 0 {
                    anyhow::bail!("injected conversion failure after copy");
                }
                assert_eq!(state.commit_sequence, 7);
                Ok(())
            }),
        );
        assert!(target.initialize(init.clone()).await.is_err());
        assert!(!target_path.exists());
        assert!(
            target.initialize(init).await.is_err(),
            "normal initialization repeats the saved failure, not the SQL"
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        let mut files = tokio::fs::read_dir(directory.path()).await?;
        let mut preparation = None;
        while let Some(entry) = files.next_entry().await? {
            if entry
                .file_name()
                .to_string_lossy()
                .starts_with(".history-current.sqlite.prepare-")
                && entry
                    .path()
                    .extension()
                    .is_some_and(|extension| extension == "sqlite")
            {
                preparation = Some(entry.path());
            }
        }
        let prepared =
            connect_read_only(&preparation.context("owned failed preparation is retained")?)
                .await?;
        assert!(
            CurrentMigrator {
                thread_id: "retry".into(),
                origin: None,
                failure: Default::default(),
                fault: Default::default(),
            }
            .get_applied_migrations_read_only(&prepared)
            .await?
            .is_empty()
        );
        prepared.close().await?;
        target.retry_initialization().await?;
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        assert_eq!(target.watermark().await?, 7);
        assert_eq!(applied_write_seq(db).await?, 7);
        Ok(())
    }

    #[tokio::test]
    async fn publication_confirmation_loss_rechecks_the_same_completed_target() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let target_path = directory.path().join("history-current.sqlite");
        let history = HistoryStore::open(&target_path, "confirmation").await?;
        history
            .state
            .fail_publication_confirmation
            .store(true, Ordering::Release);
        assert!(
            history
                .initialize(HistoryInitialization::New)
                .await
                .is_err()
        );
        let before = inspect_ready(&target_path, "confirmation").await?;
        assert!(
            history.watermark().await.is_err(),
            "a failed owner cannot publish writer admission"
        );
        history.retry_initialization().await?;
        assert_eq!(inspect_ready(&target_path, "confirmation").await?, before);
        assert_eq!(history.watermark().await?, 0);
        Ok(())
    }

    #[tokio::test]
    async fn corrupt_mixed_and_contradictory_v2_sources_are_refused_without_publication()
    -> Result<()> {
        for (fault, sql) in [
            ("digest", "UPDATE history_fact_receipts SET digest='wrong'"),
            (
                "kind",
                "UPDATE history_items SET kind='future' WHERE ordinal=1",
            ),
            (
                "mixed",
                "INSERT INTO seaql_migrations(version,applied_at) VALUES('m20261026_000000_history_adopt_nine',0)",
            ),
            (
                "gap",
                "DELETE FROM seaql_migrations WHERE version='m20261026_000003_history_input_bindings'",
            ),
            ("format", "UPDATE history_meta SET schema_version=9"),
            ("table", "DROP TABLE history_message_identities"),
        ] {
            let directory = tempfile::tempdir()?;
            let source_path = directory.path().join("history.sqlite");
            let source = seeded_source(&source_path, "corrupt").await?;
            let db = &source.writer().await?.db;
            db.execute_unprepared(sql).await?;
            let main = tokio::fs::read(&source_path).await?;
            let wal = tokio::fs::read(directory.path().join("history.sqlite-wal")).await?;
            let target_path = directory.path().join("history-current.sqlite");
            let target = HistoryStore::open(&target_path, "corrupt").await?;
            assert!(
                target
                    .initialize(origin(&source_path, "corrupt", Arc::new(|_| Ok(()))))
                    .await
                    .is_err(),
                "{fault}"
            );
            assert!(!target_path.exists(), "{fault}");
            assert_eq!(tokio::fs::read(&source_path).await?, main, "{fault}");
            assert_eq!(
                tokio::fs::read(directory.path().join("history.sqlite-wal")).await?,
                wal,
                "{fault}"
            );
        }
        Ok(())
    }

    #[tokio::test]
    async fn unregistered_source_structure_rejects_import_without_losing_source_facts() -> Result<()>
    {
        for (case, damage, restore, error) in [
            (
                "unknown-table",
            "CREATE TABLE sqlitex_unknown_authority(id INTEGER PRIMARY KEY, payload TEXT NOT NULL);
                 INSERT INTO sqlitex_unknown_authority VALUES(1,'preserve unknown source authority')"
                    .to_owned(),
                "DROP TABLE sqlitex_unknown_authority".to_owned(),
                "unknown authoritative schema object",
            ),
            (
                "extra-virtual",
                "ALTER TABLE history_items ADD COLUMN future_col TEXT GENERATED ALWAYS AS (item_id) VIRTUAL".to_owned(),
                "ALTER TABLE history_items DROP COLUMN future_col".to_owned(),
                "column",
            ),
            (
                "extra-stored",
                rebuild_meta_columns(MetaColumnFixture::ExtraStored),
                rebuild_meta_columns(MetaColumnFixture::Ordinary),
                "column",
            ),
            (
                "required-virtual",
                rebuild_meta_columns(MetaColumnFixture::VirtualFence),
                rebuild_meta_columns(MetaColumnFixture::Ordinary),
                "column",
            ),
            (
                "required-stored",
                rebuild_meta_columns(MetaColumnFixture::StoredFence),
                rebuild_meta_columns(MetaColumnFixture::Ordinary),
                "column",
            ),
            (
                "framework-virtual",
                "ALTER TABLE seaql_migrations ADD COLUMN future_col TEXT GENERATED ALWAYS AS (version) VIRTUAL".to_owned(),
                "ALTER TABLE seaql_migrations DROP COLUMN future_col".to_owned(),
                "column",
            ),
        ] {
            let directory = tempfile::tempdir()?;
            let source_path = directory.path().join("history.sqlite");
            let source = seeded_source(&source_path, "source-structure").await?;
            let db = &source.writer().await?.db;
            schema::source_format(db, "source-structure").await?;
            db.execute_unprepared(&damage).await?;
        let original = super::super::test_support::source_evidence(&source_path).await?;
        assert!(
                !tokio::fs::read(source_path.with_file_name("history.sqlite-wal"))
            .await?
                    .is_empty(),
                "{case}: source fixture must retain its committed WAL"
        );
            let target_path = directory.path().join("history-current.sqlite");
            let target = HistoryStore::open(&target_path, "source-structure").await?;
            let Err(failure) = target
                .initialize(origin(&source_path, "source-structure", Arc::new(|_| Ok(()))))
                .await
            else {
                panic!("{case}: a valid v2 prefix cannot authorize omitting unknown source structure");
            };
            assert!(format!("{failure:#}").contains(error), "{case}: {failure:#}");
            super::super::test_support::assert_pending(&target_path).await?;
            assert!(target.checkpoint().await.is_err(), "{case}");
            assert_eq!(
                super::super::test_support::source_evidence(&source_path).await?,
                original,
                "{case}: all source columns, original bytes and WAL remain unchanged"
            );
            if case == "unknown-table" {
                assert_eq!(
                    db.query_one_raw(statement(
                        "SELECT payload FROM sqlitex_unknown_authority WHERE id=1",
                        vec![]
                    ))
                    .await?
                    .context("retained unknown table row")?
                    .try_get::<String>("", "payload")?,
                    "preserve unknown source authority"
                );
    }
            // Only this test's fixture owner restores the damaged source, after proving rejection
            // and preservation. Production never removes unknown columns or silently retries.
            db.execute_unprepared(&restore).await?;
            schema::source_format(db, "source-structure").await?;
            let repaired = super::super::test_support::source_evidence(&source_path).await?;
            assert!(target.checkpoint().await.is_err(), "failure remains retained");
            target.retry_initialization().await?;
            super::super::test_support::assert_current(&target_path, "source-structure").await?;
            assert_eq!(target.watermark().await?, 7, "{case}");
            assert_eq!(
                serde_json::to_value(target.checkpoint().await?.context("repaired import")?)?,
                serde_json::to_value(
                    checkpoint::read(db, "source-structure")
                        .await?
                        .context("source checkpoint")?
                )?,
                "{case}"
            );
            assert_eq!(
                super::super::test_support::source_evidence(&source_path).await?,
                repaired,
                "{case}: explicit retry is still read-only for the repaired source"
            );
        }
        Ok(())
    }

    #[tokio::test]
    async fn unregistered_current_structure_is_rejected_by_cold_and_warm_reads() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let source_path = directory.path().join("history.sqlite");
        let source = seeded_source(&source_path, "unique-target").await?;
        source
            .writer()
            .await?
            .db
            .execute_unprepared(
                "CREATE INDEX released_optional_nonunique ON history_items(kind DESC,ordinal)",
            )
            .await?;
        let original = super::super::test_support::source_evidence(&source_path).await?;
        let uniqueness = [
            (
                "framework-ledger",
                "CREATE UNIQUE INDEX extra_unique ON seaql_migrations(applied_at)",
            ),
            (
                "extra-key-empty",
                "CREATE UNIQUE INDEX extra_unique ON history_items(kind)",
            ),
            (
                "extra-key",
                "CREATE UNIQUE INDEX extra_unique ON history_items(kind)",
            ),
            (
                "expression",
                "CREATE UNIQUE INDEX extra_unique ON history_items(lower(item_id))",
            ),
            (
                "partial",
                "CREATE UNIQUE INDEX extra_unique ON history_items(item_id) WHERE 0",
            ),
            (
                "descending",
                "CREATE UNIQUE INDEX extra_unique ON history_items(item_id DESC)",
            ),
            (
                "collation",
                "CREATE UNIQUE INDEX extra_unique ON history_items(item_id COLLATE NOCASE)",
            ),
            (
                "order",
                "CREATE UNIQUE INDEX extra_unique ON session_costs(currency,purpose)",
            ),
            (
                "duplicate",
                "CREATE UNIQUE INDEX extra_unique ON history_items(item_id)",
            ),
            (
                "integer-pk-table",
                "CREATE UNIQUE INDEX extra_unique ON history_meta(thread_id)",
            ),
        ];
        let generated = [
            (
                "extra-virtual",
                "ALTER TABLE history_items ADD COLUMN future_col TEXT GENERATED ALWAYS AS (item_id) VIRTUAL".to_owned(),
                "ALTER TABLE history_items DROP COLUMN future_col".to_owned(),
                "column",
            ),
            (
                "extra-stored",
                rebuild_meta_columns(MetaColumnFixture::ExtraStored),
                rebuild_meta_columns(MetaColumnFixture::Ordinary),
                "column",
            ),
            (
                "required-virtual",
                rebuild_meta_columns(MetaColumnFixture::VirtualFence),
                rebuild_meta_columns(MetaColumnFixture::Ordinary),
                "column",
            ),
            (
                "required-stored",
                rebuild_meta_columns(MetaColumnFixture::StoredFence),
                rebuild_meta_columns(MetaColumnFixture::Ordinary),
                "column",
            ),
            (
                "framework-virtual",
                "ALTER TABLE seaql_migrations ADD COLUMN future_col TEXT GENERATED ALWAYS AS (version) VIRTUAL".to_owned(),
                "ALTER TABLE seaql_migrations DROP COLUMN future_col".to_owned(),
                "column",
            ),
        ];
        for (case, sql, restore, error) in uniqueness
            .into_iter()
            .map(|(case, sql)| {
                (
                    case,
                    sql.to_owned(),
                    "DROP INDEX extra_unique".to_owned(),
                    "unique constraint",
                )
            })
            .chain(generated)
        {
            let target_path = directory.path().join(format!("current-{case}.sqlite"));
            let target = HistoryStore::open(&target_path, "unique-target").await?;
            if case == "extra-key-empty" {
                target.initialize(HistoryInitialization::New).await?;
                assert!(target.checkpoint().await?.is_none());
            } else {
                target
                    .initialize(origin(&source_path, "unique-target", Arc::new(|_| Ok(()))))
                    .await?;
                assert!(
                    target.checkpoint().await?.is_some(),
                    "legal PK autoindexes and optional source nonunique indexes must remain accepted"
                );
            }
            let turns = ["unused".to_owned()];
            let limits = InputChainReadLimits::new(16_384, 8 * 1024 * 1024)?;
            let expected = target.input_chains_for_turns(&turns, limits).await?;
            let mutations = connect(&target_path).await?;
            mutations.execute_unprepared(&sql).await?;
            mutations.close().await?;
            let broken = super::super::test_support::source_evidence(&target_path).await?;
            let cold = HistoryStore::open(&target_path, "unique-target").await?;
            let Err(readable) = cold.checkpoint().await else {
                panic!("{case}: unregistered target structure cannot be readable");
            };
            assert!(
                format!("{readable:#}").contains(error),
                "{case}: {readable:#}"
            );
            let Err(prepared) = target.prepare_activation().await else {
                panic!("{case}: unregistered target structure cannot be ready");
            };
            assert!(
                format!("{prepared:#}").contains(error),
                "{case}: {prepared:#}"
            );
            let Err(proof) = target.input_chains_for_turns(&turns, limits).await else {
                panic!("{case}: cached proofs recheck constraints in their own snapshot");
            };
            assert!(format!("{proof:#}").contains(error), "{case}: {proof:#}");
            assert_eq!(
                super::super::test_support::source_evidence(&target_path).await?,
                broken
            );
            assert_eq!(
                super::super::test_support::source_evidence(&source_path).await?,
                original
            );
            let mutations = connect(&target_path).await?;
            mutations.execute_unprepared(&restore).await?;
            mutations.close().await?;
            super::super::test_support::assert_current(&target_path, "unique-target").await?;
            assert_eq!(
                target.input_chains_for_turns(&turns, limits).await?,
                expected,
                "{case}: the original warm reader accepts the explicitly repaired fixture"
            );
            assert_eq!(
                super::super::test_support::source_evidence(&source_path).await?,
                original
            );
        }
        Ok(())
    }

    #[tokio::test]
    async fn panicked_preparation_is_retained_and_cannot_be_retried_as_a_failed_migration()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let source_path = directory.path().join("history.sqlite");
        let source = seeded_source(&source_path, "panic").await?;
        source.writer().await?.db.execute_unprepared("DELETE FROM seaql_migrations WHERE version='m20261026_000008_history_execution_identity'").await?;
        let target_path = directory.path().join("history-current.sqlite");
        let coordinator = super::super::super::coordinator::ThreadPersistenceCoordinator::default();
        let target = coordinator
            .install_shared_history("panic", &HistoryStore::open(&target_path, "panic").await?);
        let count = Arc::new(AtomicUsize::new(0));
        let invoked = count.clone();
        let init = origin(
            &source_path,
            "panic",
            Arc::new(move |_| {
                invoked.fetch_add(1, Ordering::SeqCst);
                panic!("injected identity converter panic");
            }),
        );
        assert!(target.initialize(init.clone()).await.is_err());
        assert!(target.retry_initialization().await.is_err());
        assert!(target.initialize(init).await.is_err());
        coordinator.retry_history_initializations().await?;
        assert_eq!(count.load(Ordering::SeqCst), 1);
        assert!(!target_path.exists());
        Ok(())
    }

    #[tokio::test]
    async fn cancelled_initialization_waiter_keeps_one_owned_job_and_shutdown_drains_it()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history-current.sqlite");
        let coordinator = super::super::super::coordinator::ThreadPersistenceCoordinator::default();
        let raw = HistoryStore::open(&path, "cancel").await?;
        let history = coordinator.install_shared_history("cancel", &raw);
        let share = history.shared();
        let (entered, release) = history.arm_init_gate().await;
        let worker_history = history.clone();
        let waiter =
            tokio::spawn(
                async move { worker_history.initialize(HistoryInitialization::New).await },
            );
        entered.await?;
        waiter.abort();
        assert!(waiter.await.unwrap_err().is_cancelled());
        drop(raw);
        drop(history);
        let same = coordinator
            .shared_history("cancel")
            .context("registry retains cancelled preparation owner")?;
        assert!(HistoryStore::from_share(&share).is_some());
        let in_flight_retry = coordinator.retry_history_initializations().await;
        release
            .send(())
            .map_err(|_| anyhow::anyhow!("preparation worker disappeared"))?;
        let drained = coordinator.drain_history_preparations().await;
        in_flight_retry?;
        drained?;
        assert_eq!(same.watermark().await?, 0);
        assert_eq!(
            inspect_ready(&path, "cancel").await?.1,
            HISTORY_SCHEMA_VERSION
        );
        drop(same);
        assert!(
            HistoryStore::from_share(&share).is_none(),
            "successful preparation must not pin a cold owner"
        );
        Ok(())
    }
}

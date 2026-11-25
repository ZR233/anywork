use std::{
    path::Path,
    sync::{Arc, Mutex},
    time::Duration,
};

use sea_orm::{
    ConnectionTrait, Database, DatabaseConnection, SqliteTransactionMode, TransactionOptions,
    TransactionTrait,
};
use sea_orm_migration::{DbErr, MigrationName, MigrationTrait, MigratorTraitSelf, SchemaManager};

use super::{HistoryError, Result, db::statement};

pub(super) const MIGRATION_V25: &str = "m20261116_000001_append_only_history";
pub(super) const MIGRATION_V26: &str = "m20261119_000026_atomic_event_history";
pub(super) const MIGRATION_V27: &str = "m20261125_000027_boundary_role_and_sparse_indexes";

pub(super) type StageUpgradeReport =
    Box<dyn FnOnce(super::upgrade::ImportCounts) -> Result<()> + Send>;

fn known_legacy_versions() -> &'static std::collections::BTreeSet<String> {
    static VERSIONS: std::sync::OnceLock<std::collections::BTreeSet<String>> =
        std::sync::OnceLock::new();
    VERSIONS.get_or_init(|| {
        let mut versions: std::collections::BTreeSet<String> = FROZEN_V24_MIGRATION_NAMES
            .iter()
            .map(|name| (*name).to_owned())
            .collect();
        versions.insert(MIGRATION_V25.to_owned());
        versions.insert(MIGRATION_V26.to_owned());
        versions
    })
}

/// Names already recorded in `seaql_migrations` for a frozen v1..v24 history.
///
/// Schema 26 upgrade never executes these steps. SeaORM only needs the applied names in its
/// migrator list so it can skip them; constructing the 34 migration structs just to read those
/// names is startup work with no production effect.
const FROZEN_V24_MIGRATION_NAMES: &[&str] = &[
    "m20261026_000001_history_schema",
    "m20261026_000002_history_input_presentation",
    "m20261026_000003_history_input_bindings",
    "m20261026_000004_history_context_sources",
    "m20261026_000005_history_tool_answers",
    "m20261026_000006_history_checkpoint_v5",
    "m20261027_000001_history_retire_ordinals",
    "m20261028_000001_history_metering_facts",
    "m20261027_000002_history_producer_payloads",
    "m20261027_000003_history_review_receipt",
    "m20261027_000004_history_atomic_timeline",
    "m20261028_000002_history_combined_content",
    "m20261029_000001_history_demand_conversation",
    "m20261101_000010_history_model_route_head",
    "m20261102_000001_history_atom_metadata",
    "m20261107_000001_history_member_read_metadata",
    "m20261104_000001_history_background_results",
    "m20261103_000001_history_timeline_items",
    "m20261108_000001_history_timeline_thinking_summary",
    "m20261108_000001_history_source_classification",
    "m20261109_000001_history_timeline_background_tail",
    "m20261109_000001_history_completion_boundary",
    "m20261110_000001_history_immutable_completion_runs",
    "m20261109_000001_display_snapshots",
    "m20261111_000001_display_observations",
    "m20261112_000001_history_tool_work",
    "m20261112_000001_visible_tail_workgroups",
    "m20261113_000001_work_snapshots",
    "m20261113_000002_display_block_order",
    "m20261114_000001_execution_facts",
    "m20261027_000004_history_project_kind",
    "m20261026_000007_history_model_access",
    "m20261026_000007a_history_workspace_receipt",
    "m20261026_000007b_history_bot_root_relocation",
    "m20261026_000008_history_execution_identity",
];

fn applied_legacy_placeholders(applied: &[String]) -> Vec<Box<dyn MigrationTrait>> {
    FROZEN_V24_MIGRATION_NAMES
        .iter()
        .filter(|name| applied.iter().any(|version| version == *name))
        .map(|name| Box::new(AlreadyAppliedLegacy { name }) as Box<dyn MigrationTrait>)
        .collect()
}

struct AlreadyAppliedLegacy {
    name: &'static str,
}

impl MigrationName for AlreadyAppliedLegacy {
    fn name(&self) -> &str {
        self.name
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for AlreadyAppliedLegacy {
    async fn up(&self, _manager: &SchemaManager) -> std::result::Result<(), DbErr> {
        Err(DbErr::Migration(format!(
            "expected {} to already be applied before the Schema 26 upgrade",
            self.name
        )))
    }
}

async fn legacy_versions(db: &DatabaseConnection) -> Result<Vec<String>> {
    let rows = db
        .query_all_raw(statement(
            "SELECT version FROM seaql_migrations ORDER BY version",
            vec![],
        ))
        .await?;
    let mut versions = Vec::with_capacity(rows.len());
    for row in rows {
        let version: String = row.try_get("", "version")?;
        if !known_legacy_versions().contains(&version) {
            return Err(HistoryError::Integrity(format!(
                "unknown legacy history migration {version}"
            )));
        }
        versions.push(version);
    }
    Ok(versions)
}

/// Initializes an empty DB directly into Schema 27.
struct FreshSchema27Migration {
    thread_id: String,
    database_id: String,
}

impl MigrationName for FreshSchema27Migration {
    fn name(&self) -> &str {
        MIGRATION_V27
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for FreshSchema27Migration {
    fn use_transaction(&self) -> Option<bool> {
        Some(false)
    }

    async fn up(&self, manager: &SchemaManager) -> std::result::Result<(), DbErr> {
        let db = manager.get_connection();
        db.execute_unprepared(include_str!("schema.sql")).await?;
        db.execute_raw(statement(
            "INSERT INTO history_store_meta(singleton,schema_version,database_id,thread_id) VALUES(1,27,?,?)",
            vec![self.database_id.clone().into(), self.thread_id.clone().into()],
        ))
        .await?;
        super::upgrade::schema26_manifest::mark_repaired(db).await?;
        Ok(())
    }
}

/// Step 1 of v24->v25->v26 chained upgrade: creates Schema 25 tables and imports v24 rows.
struct MigrationV25Import {
    thread_id: String,
    database_id: String,
    source: super::import::V24HistorySource,
    source_watermark: u64,
    stage_report: Arc<Mutex<Option<StageUpgradeReport>>>,
}

impl MigrationName for MigrationV25Import {
    fn name(&self) -> &str {
        MIGRATION_V25
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for MigrationV25Import {
    fn use_transaction(&self) -> Option<bool> {
        Some(false)
    }

    async fn up(&self, manager: &SchemaManager) -> std::result::Result<(), DbErr> {
        let db = manager.get_connection();
        let stage_report = self
            .stage_report
            .lock()
            .map_err(|_| DbErr::Migration("pending report stage lock poisoned".into()))?
            .take();
        db.execute_unprepared(include_str!("upgrade/schema_v25.sql"))
            .await?;
        db.execute_raw(statement(
            "INSERT INTO history_store_meta(singleton,schema_version,database_id,thread_id) VALUES(1,25,?,?)",
            vec![self.database_id.clone().into(), self.thread_id.clone().into()],
        ))
        .await?;
        let counts = super::upgrade::import_database(
            db,
            &self.source,
            &self.database_id,
            &self.thread_id,
            self.source_watermark,
        )
        .await
        .map_err(|error| DbErr::Migration(format!("{error:#}")))?;
        if let Some(stage_report) = stage_report {
            stage_report(counts).map_err(|error| {
                DbErr::Migration(format!("schema 25->26 report staging failed: {error:#}"))
            })?;
        }
        Ok(())
    }
}

type StageV25Report = Arc<Mutex<Option<Box<dyn FnOnce(u64) -> Result<()> + Send>>>>;

/// Transforms a Schema 25 database in-place (zero BLOB copy) into Schema 26.
struct MigrationV26Upgrade {
    thread_id: String,
    stage_v25_report: Option<StageV25Report>,
}

impl MigrationName for MigrationV26Upgrade {
    fn name(&self) -> &str {
        MIGRATION_V26
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for MigrationV26Upgrade {
    fn use_transaction(&self) -> Option<bool> {
        Some(false)
    }

    async fn up(&self, manager: &SchemaManager) -> std::result::Result<(), DbErr> {
        let db = manager.get_connection();
        let stage_report = match &self.stage_v25_report {
            Some(slot) => slot
                .lock()
                .map_err(|_| DbErr::Migration("pending report stage lock poisoned".into()))?
                .take(),
            None => None,
        };
        let (_, migrated_rows) = super::upgrade::migrate_v25_to_v26(db, &self.thread_id)
            .await
            .map_err(|error| DbErr::Migration(format!("{error:#}")))?;
        if let Some(stage_report) = stage_report {
            stage_report(migrated_rows).map_err(|error| {
                DbErr::Migration(format!("schema 25->26 report staging failed: {error:#}"))
            })?;
        }
        Ok(())
    }
}

/// Transforms a Schema 26 database in-place (zero BLOB copy) into Schema 27.
struct MigrationV27Upgrade {
    thread_id: String,
    stage_v26_report: Option<StageV25Report>,
}

impl MigrationName for MigrationV27Upgrade {
    fn name(&self) -> &str {
        MIGRATION_V27
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for MigrationV27Upgrade {
    fn use_transaction(&self) -> Option<bool> {
        Some(false)
    }

    async fn up(&self, manager: &SchemaManager) -> std::result::Result<(), DbErr> {
        let db = manager.get_connection();
        let stage_report = match &self.stage_v26_report {
            Some(slot) => slot
                .lock()
                .map_err(|_| DbErr::Migration("pending report stage lock poisoned".into()))?
                .take(),
            None => None,
        };
        let (_, migrated_rows) = super::upgrade::migrate_v26_to_v27(db, &self.thread_id)
            .await
            .map_err(|error| DbErr::Migration(format!("{error:#}")))?;
        if let Some(stage_report) = stage_report {
            stage_report(migrated_rows).map_err(|error| {
                DbErr::Migration(format!("schema 26->27 report staging failed: {error:#}"))
            })?;
        }
        Ok(())
    }
}

enum MigratorKind {
    Fresh {
        thread_id: String,
    },
    V24ToV27 {
        thread_id: String,
        legacy_versions: Vec<String>,
        database_id: String,
        source: super::import::V24HistorySource,
        source_watermark: u64,
        stage_report: Arc<Mutex<Option<StageUpgradeReport>>>,
    },
    V25ToV27 {
        thread_id: String,
        legacy_versions: Vec<String>,
        stage_v25_report: StageV25Report,
    },
    V26ToV27 {
        thread_id: String,
        legacy_versions: Vec<String>,
        stage_v26_report: StageV25Report,
    },
}

impl MigratorKind {
    fn thread_id(&self) -> &str {
        match self {
            Self::Fresh { thread_id }
            | Self::V24ToV27 { thread_id, .. }
            | Self::V25ToV27 { thread_id, .. }
            | Self::V26ToV27 { thread_id, .. } => thread_id,
        }
    }
}

struct Migrator {
    kind: MigratorKind,
}

impl MigratorTraitSelf for Migrator {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        match &self.kind {
            MigratorKind::Fresh { thread_id } => vec![Box::new(FreshSchema27Migration {
                thread_id: thread_id.clone(),
                database_id: uuid::Uuid::new_v4().to_string(),
            })],
            MigratorKind::V24ToV27 {
                thread_id,
                legacy_versions,
                database_id,
                source,
                source_watermark,
                stage_report,
            } => {
                let mut migrations = applied_legacy_placeholders(legacy_versions);
                migrations.push(Box::new(MigrationV25Import {
                    thread_id: thread_id.clone(),
                    database_id: database_id.clone(),
                    source: source.clone(),
                    source_watermark: *source_watermark,
                    stage_report: stage_report.clone(),
                }));
                migrations.push(Box::new(MigrationV26Upgrade {
                    thread_id: thread_id.clone(),
                    stage_v25_report: None,
                }));
                migrations.push(Box::new(MigrationV27Upgrade {
                    thread_id: thread_id.clone(),
                    stage_v26_report: None,
                }));
                migrations
            }
            MigratorKind::V25ToV27 {
                thread_id,
                legacy_versions,
                stage_v25_report,
            } => {
                let mut migrations = applied_legacy_placeholders(legacy_versions);
                // Dummy MigrationV25 placeholder if already in seaql_migrations (SeaORM skips applied names).
                migrations.push(Box::new(AlreadyAppliedV25Placeholder));
                migrations.push(Box::new(MigrationV26Upgrade {
                    thread_id: thread_id.clone(),
                    stage_v25_report: Some(stage_v25_report.clone()),
                }));
                migrations.push(Box::new(MigrationV27Upgrade {
                    thread_id: thread_id.clone(),
                    stage_v26_report: None,
                }));
                migrations
            }
            MigratorKind::V26ToV27 {
                thread_id,
                legacy_versions,
                stage_v26_report,
            } => {
                let mut migrations = applied_legacy_placeholders(legacy_versions);
                if legacy_versions
                    .iter()
                    .any(|version| version == MIGRATION_V25)
                {
                    migrations.push(Box::new(AlreadyAppliedV25Placeholder));
                }
                migrations.push(Box::new(AlreadyAppliedV26Placeholder));
                migrations.push(Box::new(MigrationV27Upgrade {
                    thread_id: thread_id.clone(),
                    stage_v26_report: Some(stage_v26_report.clone()),
                }));
                migrations
            }
        }
    }
}

struct AlreadyAppliedV25Placeholder;
impl MigrationName for AlreadyAppliedV25Placeholder {
    fn name(&self) -> &str {
        MIGRATION_V25
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for AlreadyAppliedV25Placeholder {
    async fn up(&self, _manager: &SchemaManager) -> std::result::Result<(), DbErr> {
        Err(DbErr::Migration(
            "expected m20261116_000001_append_only_history to already be applied in Schema 25"
                .into(),
        ))
    }
}

struct AlreadyAppliedV26Placeholder;
impl MigrationName for AlreadyAppliedV26Placeholder {
    fn name(&self) -> &str {
        MIGRATION_V26
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for AlreadyAppliedV26Placeholder {
    async fn up(&self, _manager: &SchemaManager) -> std::result::Result<(), DbErr> {
        Err(DbErr::Migration(
            "expected m20261119_000026_atomic_event_history to already be applied in Schema 26"
                .into(),
        ))
    }
}

pub(super) async fn connect(
    path: &Path,
    read_only: bool,
    create: bool,
) -> Result<DatabaseConnection> {
    connect_with_fk(path, read_only, create, true).await
}

/// Opens a read-write WAL connection with `PRAGMA foreign_keys = OFF` strictly for `history_events`
/// table replacement during Schema 25 -> 26 migration; `v25_to_v26` checks `PRAGMA foreign_key_check`
/// before committing.
pub(super) async fn connect_for_migration(path: &Path) -> Result<DatabaseConnection> {
    connect_with_fk(path, false, false, false).await
}

async fn connect_with_fk(
    path: &Path,
    read_only: bool,
    create: bool,
    foreign_keys: bool,
) -> Result<DatabaseConnection> {
    use crate::studio::paths::{SqliteFileMode, sqlite_file_options};
    use sea_orm::sqlx::sqlite::{SqliteJournalMode, SqliteSynchronous};
    let mode = if read_only {
        SqliteFileMode::ReadOnly
    } else if create {
        SqliteFileMode::Create
    } else {
        SqliteFileMode::ReadWrite
    };
    let mut options = sqlite_file_options(path, mode, move |options| {
        let options = options
            .foreign_keys(foreign_keys)
            .busy_timeout(Duration::from_secs(5));
        if read_only {
            options
        } else {
            options
                .journal_mode(SqliteJournalMode::Wal)
                .synchronous(SqliteSynchronous::Full)
        }
    })
    .await?;
    options
        .max_connections(if read_only { 4 } else { 1 })
        .min_connections(1)
        .sqlx_logging(false);
    Ok(Database::connect(options).await?)
}

pub(super) async fn initialize(db: &DatabaseConnection, thread_id: &str) -> Result<()> {
    run_immediate(
        Migrator {
            kind: MigratorKind::Fresh {
                thread_id: thread_id.into(),
            },
        },
        db,
    )
    .await?;
    Ok(())
}

pub(super) async fn run_upgrade_v24(
    db: &DatabaseConnection,
    thread_id: &str,
    database_id: &str,
    source_watermark: u64,
    source: super::import::V24HistorySource,
    stage_report: StageUpgradeReport,
) -> Result<()> {
    let stage_report = Arc::new(Mutex::new(Some(stage_report)));
    run_immediate(
        Migrator {
            kind: MigratorKind::V24ToV27 {
                thread_id: thread_id.into(),
                legacy_versions: legacy_versions(db).await?,
                database_id: database_id.to_owned(),
                source,
                source_watermark,
                stage_report,
            },
        },
        db,
    )
    .await?;
    Ok(())
}

pub(super) async fn run_upgrade_v25(
    db: &DatabaseConnection,
    thread_id: &str,
    stage_v25_report: Box<dyn FnOnce(u64) -> Result<()> + Send>,
) -> Result<()> {
    let stage_v25_report = Arc::new(Mutex::new(Some(stage_v25_report)));
    run_immediate(
        Migrator {
            kind: MigratorKind::V25ToV27 {
                thread_id: thread_id.into(),
                legacy_versions: legacy_versions(db).await?,
                stage_v25_report,
            },
        },
        db,
    )
    .await?;
    Ok(())
}

pub(super) async fn run_upgrade_v26(
    db: &DatabaseConnection,
    thread_id: &str,
    stage_v26_report: Box<dyn FnOnce(u64) -> Result<()> + Send>,
) -> Result<()> {
    let stage_v26_report = Arc::new(Mutex::new(Some(stage_v26_report)));
    run_immediate(
        Migrator {
            kind: MigratorKind::V26ToV27 {
                thread_id: thread_id.into(),
                legacy_versions: legacy_versions(db).await?,
                stage_v26_report,
            },
        },
        db,
    )
    .await?;
    Ok(())
}

async fn run_immediate(migrator: Migrator, db: &DatabaseConnection) -> Result<()> {
    let thread_id = migrator.kind.thread_id().to_owned();
    let tx = db
        .begin_with_options(TransactionOptions {
            sqlite_transaction_mode: Some(SqliteTransactionMode::Immediate),
            ..Default::default()
        })
        .await?;
    migrator.up(&tx, None).await?;
    match tx.commit().await {
        Ok(()) => Ok(()),
        Err(commit_error) => match identity(db, &thread_id).await {
            Ok(_) => Ok(()),
            Err(_) => Err(commit_error.into()),
        },
    }
}

pub(super) async fn identity(db: &DatabaseConnection, thread_id: &str) -> Result<(String, u64)> {
    let tx = db.begin().await?;
    for table in tx
        .query_all_raw(statement(
            "SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%'",
            vec![],
        ))
        .await?
    {
        let name: String = table.try_get("", "name")?;
        if ![
            "history_store_meta",
            "history_events",
            "history_bodies",
            "history_body_chunks",
            "seaql_migrations",
        ]
        .contains(&name.as_str())
        {
            return Err(HistoryError::Integrity(format!(
                "unexpected table in schema 27 history: {name}"
            )));
        }
    }
    let row = tx
        .query_one_raw(statement(
            "SELECT schema_version,database_id,thread_id FROM history_store_meta WHERE singleton=1",
            vec![],
        ))
        .await?
        .ok_or_else(|| HistoryError::Integrity("history identity is missing".into()))?;
    if row.try_get::<i64>("", "schema_version")? != 27
        || row.try_get::<String>("", "thread_id")? != thread_id
    {
        return Err(HistoryError::Integrity(
            "history schema or Thread identity differs".into(),
        ));
    }
    let database_id: String = row.try_get("", "database_id")?;
    if database_id.is_empty() {
        return Err(HistoryError::Integrity(
            "invalid history database identity".into(),
        ));
    }
    let migration = tx
        .query_all_raw(statement("SELECT version FROM seaql_migrations", vec![]))
        .await?;
    let mut found = false;
    for row in &migration {
        let version: String = row.try_get("", "version")?;
        if version != MIGRATION_V27 && !known_legacy_versions().contains(&version) {
            return Err(HistoryError::Integrity(format!(
                "unknown history migration {version}"
            )));
        }
        if version == MIGRATION_V27 {
            found = true;
        }
    }
    if !found {
        return Err(HistoryError::Integrity(
            "unsupported history migration state".into(),
        ));
    }
    for (kind, names) in [
        (
            "table",
            &["history_events", "history_bodies", "history_body_chunks"][..],
        ),
        (
            "trigger",
            &[
                "history_events_no_update",
                "history_events_no_delete",
                "history_bodies_no_update",
                "history_bodies_no_delete",
                "history_body_chunks_no_update",
                "history_body_chunks_no_delete",
            ][..],
        ),
        (
            "index",
            &[
                "idx_events_boundaries",
                "idx_events_work",
                "history_one_anchor",
                "history_row_head",
                "history_business_anchors",
                "idx_events_entity",
                "idx_events_turn",
                "idx_events_source",
                "idx_events_call",
                "idx_events_originals_all",
                "idx_events_originals_parent",
                "idx_events_originals_text",
            ][..],
        ),
    ] {
        for name in names {
            if tx
                .query_one_raw(statement(
                    "SELECT 1 FROM sqlite_schema WHERE type=? AND name=?",
                    vec![kind.into(), (*name).into()],
                ))
                .await?
                .is_none()
            {
                return Err(HistoryError::Integrity(format!(
                    "history {kind} {name} is missing"
                )));
            }
        }
    }
    let max = tx
        .query_one_raw(statement(
            "SELECT COALESCE(MAX(seq),0) AS seq FROM history_events",
            vec![],
        ))
        .await?
        .ok_or_else(|| HistoryError::Integrity("history sequence is unavailable".into()))?;
    let head = u64::try_from(max.try_get::<i64>("", "seq")?)
        .map_err(|_| HistoryError::Integrity("negative history sequence".into()))?;
    tx.commit().await?;
    Ok((database_id, head))
}

#[cfg(test)]
mod frozen_name_tests {
    use super::FROZEN_V24_MIGRATION_NAMES;

    #[test]
    fn placeholder_names_match_the_frozen_v24_migrator() {
        let migrations = crate::studio::storage::history::frozen_v24_migrations("ledger");
        let actual: Vec<&str> = migrations.iter().map(|step| step.name()).collect();
        assert_eq!(actual, FROZEN_V24_MIGRATION_NAMES);
    }
}

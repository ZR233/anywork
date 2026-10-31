//! Official, ordered history migrations. Format numbers are only legacy import markers.
use super::*;
mod conversion;
mod sqlite_metadata;
use conversion::{
    backfill_legacy_hidden_inputs, backfill_tool_user_input, migrate_context_sources,
    migrate_unconsumed_input_bindings,
};
use sea_orm_migration::{DbErr, MigrationName, MigrationTrait, MigratorTraitSelf, SchemaManager};

#[cfg(test)]
mod atomic_tests;

struct Migrator {
    thread_id: String,
    bot_root: Option<crate::studio::startup::storage_layout::bot_roots::BotRootMove>,
    // Immutable recovery candidates are shared by the migrator's repeated pending-step queries.
    // An inline pair also bloats content-only preparation, even when this option is None.
    execution_identity: Option<
        std::sync::Arc<(
            pl_core::thread::ThreadCheckpoint,
            pl_core::thread::ThreadCheckpoint,
        )>,
    >,
}

impl MigratorTraitSelf for Migrator {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        vec![
            Box::new(CreateHistory {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(InputPresentation),
            Box::new(InputBindings),
            Box::new(ContextSources {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(ToolAnswers {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(CheckpointV5 {
                thread_id: self.thread_id.clone(),
            }),
            // This content-only step precedes the lifecycle-gated recovery steps. SeaORM
            // preserves vector order and skips applied names, including on fully recovered v8 DBs.
            Box::new(RetireOrdinals),
            Box::new(ProducerPayloads {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(ReviewReceipt {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(AtomicTimeline {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(MeteringFacts {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(CombinedContent {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(ProjectKind {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(ModelAccess {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(WorkspaceReceipt {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(BotRootRelocation {
                thread_id: self.thread_id.clone(),
                mapping: self.bot_root.clone(),
            }),
            Box::new(ExecutionIdentity {
                thread_id: self.thread_id.clone(),
                candidate: self.execution_identity.clone(),
            }),
        ]
    }
}

/// Lifecycle phases select how far to advance the one official sequence. SeaORM owns ordering,
/// pending-step detection, transactions and completion records for every phase.
pub(super) enum Preparation {
    Schema,
    ModelAccess,
    ExecutionIdentity,
}
const MODEL_ACCESS: &str = "m20261026_000007_history_model_access";
// Ordered between model-access and execution identity: cold close needs representation maintenance
// without requiring (or activating) a Mode/model/tool execution owner.
const WORKSPACE_RECEIPT: &str = "m20261026_000007a_history_workspace_receipt";
const BOT_ROOT: &str = "m20261026_000007b_history_bot_root_relocation";
pub(super) const EXECUTION_IDENTITY: &str = "m20261026_000008_history_execution_identity";
const RETIRE_ORDINALS: &str = "m20261027_000001_history_retire_ordinals";
const PRODUCER_PAYLOADS: &str = "m20261027_000002_history_producer_payloads";
const REVIEW_RECEIPT: &str = "m20261027_000003_history_review_receipt";
const ATOMIC_TIMELINE: &str = "m20261027_000004_history_atomic_timeline";
const METERING_FACTS: &str = "m20261028_000001_history_metering_facts";
const COMBINED_CONTENT: &str = "m20261028_000002_history_combined_content";
const PROJECT_KIND: &str = "m20261027_000004_history_project_kind";

// Content preparation and current-only readers share the same lifecycle boundary.
fn is_lifecycle_migration(name: &str) -> bool {
    matches!(
        name,
        PROJECT_KIND | MODEL_ACCESS | WORKSPACE_RECEIPT | BOT_ROOT | EXECUTION_IDENTITY
    )
}

pub(super) async fn prepare(
    db: &DatabaseConnection,
    thread_id: &str,
    phase: Preparation,
    execution_identity: Option<
        std::sync::Arc<(
            pl_core::thread::ThreadCheckpoint,
            pl_core::thread::ThreadCheckpoint,
        )>,
    >,
) -> Result<()> {
    prepare_with_bot_root(db, thread_id, phase, execution_identity, None).await
}

pub(super) async fn prepare_with_bot_root(
    db: &DatabaseConnection,
    thread_id: &str,
    phase: Preparation,
    execution_identity: Option<
        std::sync::Arc<(
            pl_core::thread::ThreadCheckpoint,
            pl_core::thread::ThreadCheckpoint,
        )>,
    >,
    bot_root: Option<crate::studio::startup::storage_layout::bot_roots::BotRootMove>,
) -> Result<()> {
    preflight(db, thread_id)
        .await
        .map_err(|error| crate::studio::startup::migration_error("history", "preflight", error))?;
    let migrator = Migrator {
        thread_id: thread_id.to_owned(),
        execution_identity,
        bot_root,
    };
    let pending = migrator.get_pending_migrations_read_only(db).await?;
    let steps = match phase {
        Preparation::Schema => pending
            .iter()
            .take_while(|step| !is_lifecycle_migration(step.name()))
            .count(),
        Preparation::ModelAccess => pending
            .iter()
            .take_while(|step| step.name() != EXECUTION_IDENTITY)
            .count(),
        Preparation::ExecutionIdentity => pending.len(),
    };
    if let Err(error) = migrator.up(db, Some(u32::try_from(steps)?)).await {
        let pending = migrator
            .get_pending_migrations_read_only(db)
            .await
            .unwrap_or_default();
        let step = pending
            .first()
            .map_or("migration bookkeeping", |migration| migration.name());
        return Err(crate::studio::startup::migration_error(
            "history", step, error,
        ));
    }
    Ok(())
}

pub(super) async fn initialize(db: &DatabaseConnection, thread_id: &str) -> Result<(String, i64)> {
    prepare(db, thread_id, Preparation::Schema, None).await?;
    // Publish only the actual identity/format verified after the content migrations, never an
    // assumed current version derived from a successful (possibly zero-step) preparation.
    validate_existing(db, thread_id).await
}

pub(super) async fn inspect_existing(path: &Path, thread_id: &str) -> Result<()> {
    if !tokio::fs::try_exists(path).await? {
        return Ok(());
    }
    let db = connect_read_only(path).await?;
    let result = preflight(&db, thread_id)
        .await
        .map_err(|error| crate::studio::startup::migration_error("history", "preflight", error));
    let close = db.close().await;
    result?;
    close?;
    Ok(())
}

/// Layout evidence may consult TOML only after proving this is an initialized, supported history
/// family for the same Thread. An arbitrary empty/unversioned SQLite file is not that window.
pub(crate) async fn validate_layout_source(db: &DatabaseConnection, thread_id: &str) -> Result<()> {
    preflight(db, thread_id).await?;
    ensure!(
        db.query_one_raw(statement(
            "SELECT thread_id FROM history_meta WHERE id=1",
            vec![]
        ))
        .await?
        .is_some(),
        "layout source has no initialized history identity"
    );
    Ok(())
}

async fn preflight(db: &DatabaseConnection, thread_id: &str) -> Result<()> {
    let migrator = Migrator {
        thread_id: thread_id.to_owned(),
        execution_identity: None,
        bot_root: None,
    };
    let pending = migrator.get_pending_migrations_read_only(db).await?;
    let meta = db
        .query_one_raw(statement(
            "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='history_meta'",
            vec![],
        ))
        .await?;
    if meta.is_none() {
        ensure!(db.query_one_raw(statement("SELECT 1 FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name<>'seaql_migrations' LIMIT 1", vec![])).await?.is_none(),
            "unversioned nonempty history database; existing data preserved");
        ensure!(
            migrator
                .get_applied_migrations_read_only(db)
                .await?
                .is_empty(),
            "history schema is missing; existing data preserved"
        );
        return Ok(());
    }
    let row = db
        .query_one_raw(statement(
            "SELECT schema_version,thread_id,database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("missing history identity; existing data preserved")?;
    let version: i64 = row.try_get("", "schema_version")?;
    ensure!(
        (1..=HISTORY_SCHEMA_VERSION).contains(&version),
        "unsupported history schema {version}; existing data preserved"
    );
    let atomic_pending = pending.iter().any(|step| step.name() == ATOMIC_TIMELINE);
    let metering_pending = pending.iter().any(|step| step.name() == METERING_FACTS);
    let combined_pending = pending.iter().any(|step| step.name() == COMBINED_CONTENT);
    let retire_pending = pending.iter().any(|step| step.name() == RETIRE_ORDINALS);
    // Format and migration bookkeeping must describe the same content boundary. Lifecycle
    // recovery being pending never excuses a completed content step with an older marker.
    ensure!(
        match version {
            1..=8 => retire_pending && atomic_pending && metering_pending && combined_pending,
            9 => !retire_pending && atomic_pending && metering_pending && combined_pending,
            10 => !retire_pending && (!atomic_pending || !metering_pending) && combined_pending,
            HISTORY_SCHEMA_VERSION => {
                !retire_pending && !atomic_pending && !metering_pending && !combined_pending
            }
            _ => false,
        },
        "history format conflicts with completed migrations; existing data preserved"
    );
    ensure!(
        SchemaManager::new(db).has_table("timeline_records").await? == !atomic_pending,
        "atomic timeline migration conflicts with its output table; existing data preserved"
    );
    ensure!(
        row.try_get::<String>("", "thread_id")? == thread_id,
        "history database belongs to another Thread"
    );
    ensure!(
        !row.try_get::<String>("", "database_id")?.is_empty(),
        "history database identity is empty"
    );
    validate_identity_collations(db).await?;
    if version == 8 {
        // Keep the published v8 adoption contract: CreateHistory may still add its
        // request_digest column when enrolling a pre-SeaORM file for the first time.
        let manager = SchemaManager::new(db);
        for table in [
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
            ensure!(
                manager.has_table(table).await?,
                "current history table {table} is missing; existing data preserved"
            );
        }
    } else if version == 9 || (version == 10 && atomic_pending) {
        validate_v9_tables(db).await?;
    } else if version == 10 || version == HISTORY_SCHEMA_VERSION {
        validate_tables(db).await?;
        if version == 10 {
            validate_timeline_data(db, thread_id).await?;
        }
    }
    if version == 10 && !metering_pending {
        checkpoint::read(db, thread_id).await?;
    }
    if version == HISTORY_SCHEMA_VERSION {
        ensure!(
            pending
                .iter()
                .all(|step| is_lifecycle_migration(step.name())),
            "current history format has pending content migrations; existing data preserved"
        );
    }
    if SchemaManager::new(db)
        .has_table("session_checkpoint")
        .await?
    {
        for row in db
            .query_all_raw(statement(
                "SELECT json_extract(payload,'$.schemaVersion') AS version FROM session_checkpoint",
                vec![],
            ))
            .await?
        {
            let checkpoint_version: i64 = row.try_get("", "version")?;
            ensure!(
                (1..=i64::from(pl_core::thread::ThreadCheckpoint::SCHEMA_VERSION))
                    .contains(&checkpoint_version),
                "unsupported checkpoint schema {checkpoint_version}; existing data preserved"
            );
        }
    }
    for row in db
        .query_all_raw(statement("PRAGMA quick_check", vec![]))
        .await?
    {
        ensure!(
            row.try_get_by_index::<String>(0)? == "ok",
            "history database integrity check failed"
        );
    }
    Ok(())
}

/// First-connection trust gate, before any transaction takes the pool's only connection.
/// Missing tables remain subject to the versioned adoption/shape rules in preflight; an
/// existing table must already have the exact comparison semantics its identity queries use.
pub(super) async fn validate_identity_collations(db: &DatabaseConnection) -> Result<()> {
    let manager = SchemaManager::new(db);
    for (table, columns) in [
        (
            "history_items",
            &["item_id", "turn_id", "kind", "lifecycle"][..],
        ),
        ("history_turns", &["turn_id"][..]),
        ("history_input_identities", &["item_id"][..]),
        ("history_fact_receipts", &["item_id", "kind"][..]),
        ("history_message_identities", &["message_id"][..]),
        ("current_context", &["record_id"][..]),
        ("history_tool_tasks", &["call_id"][..]),
        ("session_costs", &["purpose", "currency"][..]),
        ("timeline_records", &["record_id"][..]),
    ] {
        if !manager.has_table(table).await? {
            continue;
        }
        let declarations = db
            .query_all_raw(statement(
                "SELECT name,type FROM pragma_table_info(?, 'main')",
                vec![table.into()],
            ))
            .await?
            .into_iter()
            .map(|row| Ok((row.try_get("", "name")?, row.try_get("", "type")?)))
            .collect::<std::result::Result<
                std::collections::BTreeMap<String, String>,
                sea_orm::DbErr,
            >>()?;
        for column in columns {
            let declared = declarations
                .get(*column)
                .with_context(|| format!("history column {table}.{column} is missing"))?;
            let declared_upper = declared.to_ascii_uppercase();
            // SQLite datatype §3.1: INTEGER takes precedence over TEXT, including CHARINT.
            // The later BLOB/REAL/NUMERIC rules cannot produce TEXT. STRICT accepts only
            // canonical type names, so this also rejects its ANY rather than treating it as TEXT.
            ensure!(
                !declared_upper.contains("INT")
                    && ["CHAR", "CLOB", "TEXT"]
                        .iter()
                        .any(|marker| declared_upper.contains(marker)),
                "history column {table}.{column} requires TEXT affinity, found {declared:?}; existing data preserved"
            );
            let collation = sqlite_metadata::column_collation(db, table, column).await?;
            ensure!(
                collation.eq_ignore_ascii_case("BINARY"),
                "history column {table}.{column} requires BINARY comparison, found {collation}; existing data preserved"
            );
        }
    }
    Ok(())
}

/// Ordinary readers accept only the prepared content format; lifecycle migrations may remain
/// pending until explicit recovery supplies model and execution identity facts.
pub(super) async fn validate_current(db: &impl ConnectionTrait, thread_id: &str) -> Result<()> {
    ensure!(
        version(db).await? == HISTORY_SCHEMA_VERSION,
        "history format is not current; existing data preserved"
    );
    validate_tables(db).await?;
    let migrator = Migrator {
        thread_id: thread_id.to_owned(),
        execution_identity: None,
        bot_root: None,
    };
    ensure!(
        migrator
            .get_pending_migrations_read_only(db)
            .await?
            .iter()
            .all(|step| is_lifecycle_migration(step.name())),
        "history content requires explicit storage preparation; existing data preserved"
    );
    Ok(())
}

async fn validate_tables(db: &impl ConnectionTrait) -> Result<()> {
    validate_v9_tables(db).await?;
    db.query_all_raw(statement(
        "SELECT append_seq,record_id,turn_id,source_effect_seq,sealed_at,kind,payload FROM timeline_records LIMIT 0",
        vec![],
    ))
    .await
    .context("history timeline table or column is missing; existing data preserved")?;
    validate_keys(
        db,
        "timeline_records",
        &["append_seq"],
        true,
        &["record_id"],
    )
    .await?;
    Ok(())
}

/// Reuse the canonical record decoder without rewriting or aggregating existing completions.
/// Preparation may inspect every record, but bounds full payload memory to one ordinary page.
async fn validate_timeline_data(db: &impl ConnectionTrait, thread_id: &str) -> Result<()> {
    ensure!(
        db.query_one_raw(statement(
            "SELECT 1 FROM timeline_records WHERE append_seq<=0 LIMIT 1",
            vec![],
        ))
        .await?
        .is_none(),
        "timeline append sequence must be positive; existing data preserved"
    );
    let ceiling = super::timeline::latest_append_seq(db).await?;
    let mut after = 0;
    loop {
        let page = super::timeline::page_after(
            db,
            thread_id,
            after,
            ceiling,
            pl_core::chat::MAX_PAGE_ITEMS,
        )
        .await?;
        for item in &page.items {
            ensure!(
                after.checked_add(1) == Some(item.append_seq),
                "timeline append sequence is not contiguous; existing data preserved"
            );
            after = item.append_seq;
        }
        if !page.has_more {
            return Ok(());
        }
    }
}

/// Published v9 shape, also used by RetireOrdinals. Never add current-format tables here:
/// earlier steps must remain runnable before the AtomicTimeline step has created its output.
async fn validate_v9_tables(db: &impl ConnectionTrait) -> Result<()> {
    // Preparing each query validates required columns even on empty tables, without reading
    // history bodies or repairing a damaged current database with CREATE IF NOT EXISTS.
    for query in [
        "SELECT applied_write_seq FROM history_meta LIMIT 0",
        "SELECT ordinal,item_id,turn_id,kind,revision,lifecycle,created_at,updated_at,payload,last_write_seq FROM history_items LIMIT 0",
        "SELECT turn_id,first_ordinal,last_ordinal,revision,payload,last_write_seq FROM history_turns LIMIT 0",
        "SELECT item_id,ordinal,revision,digest,request_digest,presentation,payload,last_write_seq FROM history_input_identities LIMIT 0",
        "SELECT item_id,revision,kind,digest,payload,last_write_seq FROM history_fact_receipts LIMIT 0",
        "SELECT message_id,item_id,sequence,digest,last_write_seq FROM history_message_identities LIMIT 0",
        "SELECT id,revision,context_revision,context_count,payload,payload_hash,legacy_cleanup FROM session_checkpoint LIMIT 0",
        "SELECT purpose,currency,amount FROM session_costs LIMIT 0",
        "SELECT ordinal,record_id,payload,payload_hash FROM current_context LIMIT 0",
        "SELECT call_id,revision,task_payload,delivery_payload,last_write_seq FROM history_tool_tasks LIMIT 0",
    ] {
        db.query_all_raw(statement(query, vec![]))
            .await
            .context("history required table or column is missing; existing data preserved")?;
    }
    // These are the keys used by ordinal seeks, identity point reads and ON CONFLICT writes.
    // Check SQLite's actual constraints, not just columns or the contents of an empty database.
    for (table, primary, integer_primary, unique) in [
        ("history_meta", &["id"][..], true, &[][..]),
        ("history_items", &["ordinal"][..], true, &["item_id"][..]),
        ("history_turns", &["turn_id"][..], false, &[][..]),
        ("history_input_identities", &["item_id"][..], false, &[][..]),
        (
            "history_fact_receipts",
            &["item_id", "revision"][..],
            false,
            &[][..],
        ),
        (
            "history_message_identities",
            &["message_id"][..],
            false,
            &[][..],
        ),
        ("session_checkpoint", &["id"][..], true, &[][..]),
        (
            "session_costs",
            &["purpose", "currency"][..],
            false,
            &[][..],
        ),
        (
            "current_context",
            &["ordinal"][..],
            true,
            &["record_id"][..],
        ),
        ("history_tool_tasks", &["call_id"][..], false, &[][..]),
    ] {
        validate_keys(db, table, primary, integer_primary, unique).await?;
    }
    Ok(())
}

/// Local history key validation using SQLite's public metadata. Index names and DDL spelling
/// are immaterial; partial/expression indexes do not establish the required identity uniqueness.
async fn validate_keys(
    db: &impl ConnectionTrait,
    table: &str,
    primary: &[&str],
    integer_primary: bool,
    unique: &[&str],
) -> Result<()> {
    ensure!(
        db.query_one_raw(statement(
            "SELECT 1 FROM main.sqlite_schema WHERE type='table' AND name=?",
            vec![table.into()],
        ))
        .await?
        .is_some(),
        "history required table {table} is missing; existing data preserved"
    );
    let columns = db
        .query_all_raw(statement(
            "SELECT name,type,pk,\"notnull\" FROM pragma_table_info(?, 'main')",
            vec![table.into()],
        ))
        .await?;
    let mut actual_primary = Vec::new();
    for column in &columns {
        if column.try_get::<i64>("", "pk")? > 0 {
            actual_primary.push(column.try_get::<String>("", "name")?);
        }
    }
    ensure!(
        actual_primary.len() == primary.len()
            && primary
                .iter()
                .all(|key| actual_primary.iter().any(|name| name == key)),
        "history table {table} primary key differs from required {primary:?}; existing data preserved"
    );
    let indexes = db
        .query_all_raw(statement(
            "SELECT name,\"unique\",origin,partial FROM pragma_index_list(?, 'main')",
            vec![table.into()],
        ))
        .await?;
    if integer_primary {
        // INTEGER PRIMARY KEY is a rowid alias. In particular INTEGER PRIMARY KEY DESC
        // instead creates a nullable indexed key: table_info's pk flag alone cannot prove it.
        ensure!(
            primary.len() == 1
                && columns.iter().any(|column| {
                    column.try_get::<String>("", "name").ok().as_deref() == Some(primary[0])
                        && column
                            .try_get::<String>("", "type")
                            .is_ok_and(|kind| kind.eq_ignore_ascii_case("INTEGER"))
                })
                && indexes.iter().all(|index| index
                    .try_get::<String>("", "origin")
                    .is_ok_and(|origin| origin != "pk")),
            "history table {table} requires an INTEGER PRIMARY KEY rowid; existing data preserved"
        );
    } else {
        ensure!(
            has_unique_key(db, &indexes, primary, true).await?,
            "history table {table} primary key lacks exact identity uniqueness; existing data preserved"
        );
        // Both published composite keys (receipts and costs) declare every component NOT NULL.
        // A rowid table's PRIMARY KEY alone still admits duplicate keys containing NULL.
        // Single-column TEXT primary keys intentionally retain their published nullable shape.
        if primary.len() > 1 {
            for key in primary {
                let column = columns
                    .iter()
                    .find(|column| {
                        column.try_get::<String>("", "name").ok().as_deref() == Some(*key)
                    })
                    .context("validated history primary-key column disappeared")?;
                ensure!(
                    column.try_get::<i64>("", "notnull")? == 1,
                    "history table {table} composite primary key column {key} requires NOT NULL; existing data preserved"
                );
            }
        }
    }
    for key in unique {
        ensure!(
            columns.iter().any(|column| {
                column.try_get::<String>("", "name").ok().as_deref() == Some(*key)
                    && column
                        .try_get::<i64>("", "notnull")
                        .is_ok_and(|value| value == 1)
            }) && has_unique_key(db, &indexes, &[*key], false).await?,
            "history table {table} requires NOT NULL UNIQUE key {key}; existing data preserved"
        );
    }
    Ok(())
}

async fn has_unique_key(
    db: &impl ConnectionTrait,
    indexes: &[sea_orm::QueryResult],
    keys: &[&str],
    primary: bool,
) -> Result<bool> {
    for index in indexes {
        if index.try_get::<i64>("", "unique")? != 1
            || index.try_get::<i64>("", "partial")? != 0
            || (primary && index.try_get::<String>("", "origin")? != "pk")
        {
            continue;
        }
        let columns = db
            .query_all_raw(statement(
                "SELECT name,coll FROM pragma_index_xinfo(?, 'main') WHERE key=1",
                vec![index.try_get::<String>("", "name")?.into()],
            ))
            .await?;
        if columns.len() == keys.len()
            && keys.iter().all(|key| {
                columns.iter().any(|column| {
                    column
                        .try_get::<Option<String>>("", "name")
                        .ok()
                        .flatten()
                        .as_deref()
                        == Some(*key)
                })
            })
            && columns.iter().all(|column| {
                column
                    .try_get::<Option<String>>("", "name")
                    .is_ok_and(|name| name.is_some_and(|name| keys.contains(&name.as_str())))
                    && column
                        .try_get::<String>("", "coll")
                        .is_ok_and(|collation| collation.eq_ignore_ascii_case("BINARY"))
            })
        {
            return Ok(true);
        }
    }
    Ok(false)
}

struct RetireOrdinals;
struct MeteringFacts {
    thread_id: String,
}
impl MigrationName for MeteringFacts {
    fn name(&self) -> &str {
        METERING_FACTS
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for MeteringFacts {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        checkpoint::migrate_envelope(db, &self.thread_id)
            .await
            .map_err(conversion)?;
        super::producer::migrate(db, &self.thread_id)
            .await
            .map_err(conversion)?;
        set_version(db, 10).await
    }
}

struct ProducerPayloads {
    thread_id: String,
}
impl MigrationName for ProducerPayloads {
    fn name(&self) -> &str {
        PRODUCER_PAYLOADS
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ProducerPayloads {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        super::producer::migrate(manager.get_connection(), &self.thread_id)
            .await
            .map_err(conversion)
    }
}
impl MigrationName for RetireOrdinals {
    fn name(&self) -> &str {
        RETIRE_ORDINALS
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for RetireOrdinals {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        validate_v9_tables(db).await.map_err(conversion)?;
        db.execute_unprepared("DROP TABLE IF EXISTS history_ordinals")
            .await?;
        if version(db).await? < 9 {
            set_version(db, 9).await?;
        }
        Ok(())
    }
}

struct AtomicTimeline {
    thread_id: String,
}

impl MigrationName for AtomicTimeline {
    fn name(&self) -> &str {
        ATOMIC_TIMELINE
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for AtomicTimeline {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let source_version = version(db).await?;
        let metering_applied = Migrator {
            thread_id: self.thread_id.clone(),
            execution_identity: None,
            bot_root: None,
        }
        .get_applied_migrations_read_only(db)
        .await?
        .iter()
        .any(|step| step.name() == METERING_FACTS);
        if source_version != 9 && !(source_version == 10 && metering_applied) {
            return Err(DbErr::Migration(
                "atomic timeline migration requires history format 9 or metering-applied format 10"
                    .into(),
            ));
        }
        validate_v9_tables(db).await.map_err(conversion)?;
        super::timeline::migrate(db, &self.thread_id)
            .await
            .map_err(conversion)?;
        validate_tables(db).await.map_err(conversion)?;
        set_version(db, 10).await
    }
}

struct CombinedContent {
    thread_id: String,
}

impl MigrationName for CombinedContent {
    fn name(&self) -> &str {
        COMBINED_CONTENT
    }
}

#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CombinedContent {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let migrator = Migrator {
            thread_id: self.thread_id.clone(),
            execution_identity: None,
            bot_root: None,
        };
        if version(db).await? != 10
            || migrator
                .get_pending_migrations_read_only(db)
                .await?
                .iter()
                .any(|step| step.name() != COMBINED_CONTENT && !is_lifecycle_migration(step.name()))
        {
            return Err(DbErr::Migration(
                "combined history content requires both completed format 10 content steps".into(),
            ));
        }
        validate_tables(db).await.map_err(conversion)?;
        validate_timeline_data(db, &self.thread_id)
            .await
            .map_err(conversion)?;
        checkpoint::read(db, &self.thread_id)
            .await
            .map_err(conversion)?;
        set_version(db, HISTORY_SCHEMA_VERSION).await
    }
}

pub(super) async fn version(db: &impl ConnectionTrait) -> Result<i64, DbErr> {
    db.query_one_raw(statement(
        "SELECT schema_version FROM history_meta WHERE id=1",
        vec![],
    ))
    .await?
    .ok_or_else(|| DbErr::Migration("missing history format".into()))?
    .try_get("", "schema_version")
}
async fn set_version(db: &impl ConnectionTrait, target: i64) -> Result<(), DbErr> {
    db.execute_raw(statement(
        "UPDATE history_meta SET schema_version=? WHERE id=1",
        vec![target.into()],
    ))
    .await?;
    Ok(())
}
fn conversion(error: anyhow::Error) -> DbErr {
    match error.downcast::<DbErr>() {
        Ok(error) => error,
        Err(error) => DbErr::Migration(format!("{error:#}")),
    }
}

struct CreateHistory {
    thread_id: String,
}
impl MigrationName for CreateHistory {
    fn name(&self) -> &str {
        "m20261026_000001_history_schema"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CreateHistory {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        db.execute_unprepared(
            "CREATE TABLE IF NOT EXISTS history_meta (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            schema_version INTEGER NOT NULL,
            database_id TEXT NOT NULL,
            thread_id TEXT NOT NULL,
            applied_write_seq INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS history_items (
            ordinal INTEGER PRIMARY KEY,
            item_id TEXT NOT NULL UNIQUE,
            turn_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            revision INTEGER NOT NULL,
            lifecycle TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            payload TEXT NOT NULL CHECK (json_valid(payload)),
            last_write_seq INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS history_items_by_turn
            ON history_items(turn_id, ordinal);
        -- 最新终态按 ordinal 排序；缺口恢复另按原始 write_seq 范围读取。
        CREATE INDEX IF NOT EXISTS history_items_by_kind_lifecycle
            ON history_items(kind, lifecycle, ordinal);
        CREATE INDEX IF NOT EXISTS history_terminal_turns_by_write_seq
            ON history_items(last_write_seq,ordinal) WHERE kind='turn' AND lifecycle='terminal';
        -- `agent_page` 的 text-only 稀疏过滤同样带 ordinal 方向，单独一条 (kind, ordinal) 索引
        -- 才能同时满足过滤与排序。
        CREATE INDEX IF NOT EXISTS history_items_by_kind
            ON history_items(kind, ordinal);
        CREATE TABLE IF NOT EXISTS history_turns (
            turn_id TEXT PRIMARY KEY,
            first_ordinal INTEGER NOT NULL,
            last_ordinal INTEGER NOT NULL,
            revision INTEGER NOT NULL,
            payload TEXT NOT NULL CHECK (json_valid(payload)),
            last_write_seq INTEGER NOT NULL
        );
        -- Turn 页是 `last_ordinal` 上的 keyset 倒序扫描；没有这条索引时深翻页会退化成全表
        -- 扫描 + 排序。
        CREATE INDEX IF NOT EXISTS history_turns_by_last_ordinal
            ON history_turns(last_ordinal);
        CREATE TABLE IF NOT EXISTS history_input_identities (
            item_id TEXT PRIMARY KEY,
            ordinal INTEGER NOT NULL,
            revision INTEGER NOT NULL,
            digest TEXT NOT NULL,
            request_digest TEXT,
            presentation TEXT CHECK (presentation IN ('visible','hidden')),
            payload TEXT NOT NULL CHECK (json_valid(payload)),
            last_write_seq INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS history_fact_receipts (
            item_id TEXT NOT NULL,
            revision INTEGER NOT NULL,
            kind TEXT NOT NULL,
            digest TEXT NOT NULL,
            payload TEXT NOT NULL CHECK (json_valid(payload)),
            last_write_seq INTEGER NOT NULL,
            PRIMARY KEY(item_id, revision)
        );
        -- 已受理消息的最小身份索引：原始消息 id、时间线条目身份、受理序号与正文摘要。
        -- `digest` 可空，只用于迁移回填留下的“身份已知、正文不可验证”行（读取方 fail-closed）。
        CREATE TABLE IF NOT EXISTS history_message_identities (
            message_id TEXT PRIMARY KEY,
            item_id TEXT NOT NULL,
            sequence INTEGER NOT NULL,
            digest TEXT,
            last_write_seq INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS session_checkpoint (
            id INTEGER PRIMARY KEY CHECK(id=1),
            revision INTEGER NOT NULL,
            context_revision INTEGER NOT NULL,
            context_count INTEGER NOT NULL,
            payload TEXT NOT NULL,
            payload_hash TEXT NOT NULL,
            legacy_cleanup INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS session_costs (
            purpose TEXT NOT NULL,
            currency TEXT NOT NULL,
            amount REAL NOT NULL,
            PRIMARY KEY(purpose,currency)
        );
        CREATE TABLE IF NOT EXISTS current_context (
            ordinal INTEGER PRIMARY KEY,
            record_id TEXT NOT NULL UNIQUE,
            payload TEXT NOT NULL,
            payload_hash TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS history_tool_tasks (
            call_id TEXT PRIMARY KEY,
            revision INTEGER NOT NULL,
            task_payload TEXT NOT NULL CHECK (json_valid(task_payload)),
            delivery_payload TEXT CHECK (delivery_payload IS NULL OR json_valid(delivery_payload)),
            last_write_seq INTEGER NOT NULL
        );",
        )
        .await?;

        if !manager
            .has_column("history_input_identities", "request_digest")
            .await?
        {
            db.execute_unprepared(
                "ALTER TABLE history_input_identities ADD COLUMN request_digest TEXT",
            )
            .await?;
        }
        db.execute_raw(statement("INSERT OR IGNORE INTO history_meta(id,schema_version,database_id,thread_id,applied_write_seq) VALUES(1,?,?,?,0)",
            vec![8i64.into(), crate::studio::new_id("history-db").into(), self.thread_id.clone().into()])).await?;
        Ok(())
    }
}

struct InputPresentation;
impl MigrationName for InputPresentation {
    fn name(&self) -> &str {
        "m20261026_000002_history_input_presentation"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for InputPresentation {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await? < 3 {
            if !manager
                .has_column("history_input_identities", "presentation")
                .await?
            {
                db.execute_unprepared("ALTER TABLE history_input_identities ADD COLUMN presentation TEXT CHECK (presentation IN ('visible','hidden'))").await?;
            }
            backfill_legacy_hidden_inputs(db)
                .await
                .map_err(conversion)?;
            set_version(db, 3).await?;
        }
        Ok(())
    }
}

struct InputBindings;
impl MigrationName for InputBindings {
    fn name(&self) -> &str {
        "m20261026_000003_history_input_bindings"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for InputBindings {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await? < 4 {
            migrate_unconsumed_input_bindings(db)
                .await
                .map_err(conversion)?;
            set_version(db, 4).await?;
        }
        Ok(())
    }
}

struct ContextSources {
    thread_id: String,
}
impl MigrationName for ContextSources {
    fn name(&self) -> &str {
        "m20261026_000004_history_context_sources"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ContextSources {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await? < 6 {
            migrate_context_sources(db, &self.thread_id)
                .await
                .map_err(conversion)?;
            set_version(db, 6).await?;
        }
        Ok(())
    }
}

struct ToolAnswers {
    thread_id: String,
}
impl MigrationName for ToolAnswers {
    fn name(&self) -> &str {
        "m20261026_000005_history_tool_answers"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ToolAnswers {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        if version(db).await? < 8 {
            backfill_tool_user_input(db, &self.thread_id)
                .await
                .map_err(conversion)?;
            set_version(db, 8).await?;
        }
        Ok(())
    }
}

struct CheckpointV5 {
    thread_id: String,
}
impl MigrationName for CheckpointV5 {
    fn name(&self) -> &str {
        "m20261026_000006_history_checkpoint_v5"
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for CheckpointV5 {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        checkpoint::migrate_envelope(db, &self.thread_id)
            .await
            .map_err(conversion)?;
        Ok(())
    }
}

/// Checkpoint Project bindings predate kind. Upgrade only at the named history boundary,
/// so ordinary WorkspaceRecord decoding remains strict and old saved paths remain authoritative.
struct ProjectKind {
    thread_id: String,
}
impl MigrationName for ProjectKind {
    fn name(&self) -> &str {
        PROJECT_KIND
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ProjectKind {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }

    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let Some(original) = checkpoint::read(db, &self.thread_id)
            .await
            .map_err(conversion)?
        else {
            return Ok(());
        };
        let mut migrated = original.clone();
        crate::studio::producer_migration::project_kind(&mut migrated).map_err(conversion)?;
        checkpoint::write_representation(db, &original, &migrated)
            .await
            .map_err(conversion)
    }
}

struct ModelAccess {
    thread_id: String,
}
impl MigrationName for ModelAccess {
    fn name(&self) -> &str {
        MODEL_ACCESS
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ModelAccess {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let Some(original) = checkpoint::read(db, &self.thread_id)
            .await
            .map_err(conversion)?
        else {
            return Ok(());
        };
        let mut migrated = original.clone();
        // Absence of explicit close remains absence; core Closed never invents Studio intent.
        crate::studio::agent_close::is_explicitly_closed(&migrated.state).map_err(conversion)?;
        crate::studio::model_route::migration::upgrade(&mut migrated.state).map_err(conversion)?;
        crate::studio::delegation::migrate(&mut migrated.state).map_err(conversion)?;
        checkpoint::write_representation(db, &original, &migrated)
            .await
            .map_err(conversion)
    }
}

struct WorkspaceReceipt {
    thread_id: String,
}

/// Explicit representation maintenance also runs for databases that already applied workspace v2.
struct ReviewReceipt {
    thread_id: String,
}
impl MigrationName for ReviewReceipt {
    fn name(&self) -> &str {
        REVIEW_RECEIPT
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ReviewReceipt {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        WorkspaceReceipt {
            thread_id: self.thread_id.clone(),
        }
        .up(manager)
        .await
    }
}
impl MigrationName for WorkspaceReceipt {
    fn name(&self) -> &str {
        WORKSPACE_RECEIPT
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for WorkspaceReceipt {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let Some(original) = checkpoint::read(db, &self.thread_id)
            .await
            .map_err(conversion)?
        else {
            return Ok(());
        };
        let mut migrated = original.clone();
        crate::studio::workspace_receipt::migration::upgrade(&mut migrated.state)
            .map_err(conversion)?;
        checkpoint::write_representation(db, &original, &migrated)
            .await
            .map_err(conversion)
    }
}

struct ExecutionIdentity {
    thread_id: String,
    candidate: Option<
        std::sync::Arc<(
            pl_core::thread::ThreadCheckpoint,
            pl_core::thread::ThreadCheckpoint,
        )>,
    >,
}
impl MigrationName for ExecutionIdentity {
    fn name(&self) -> &str {
        EXECUTION_IDENTITY
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for ExecutionIdentity {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let (original, migrated) = self.candidate.as_deref().ok_or_else(|| {
            DbErr::Migration("execution identity requires explicit recovery preparation".into())
        })?;
        let db = manager.get_connection();
        let current = checkpoint::read(db, &self.thread_id)
            .await
            .map_err(conversion)?
            .ok_or_else(|| DbErr::Migration("recovery checkpoint is absent".into()))?;
        if serde_json::to_vec(&current).map_err(|error| DbErr::Migration(error.to_string()))?
            != serde_json::to_vec(original).map_err(|error| DbErr::Migration(error.to_string()))?
        {
            return Err(DbErr::Migration(
                "checkpoint changed during recovery migration; original data preserved".into(),
            ));
        }
        checkpoint::write_representation(db, original, migrated)
            .await
            .map_err(conversion)
    }
}

struct BotRootRelocation {
    thread_id: String,
    mapping: Option<crate::studio::startup::storage_layout::bot_roots::BotRootMove>,
}
impl MigrationName for BotRootRelocation {
    fn name(&self) -> &str {
        BOT_ROOT
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for BotRootRelocation {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let Some(mapping) = &self.mapping else {
            return Ok(());
        };
        let db = manager.get_connection();
        let Some(original) = checkpoint::read(db, &self.thread_id)
            .await
            .map_err(conversion)?
        else {
            return Ok(());
        };
        let mut migrated = original.clone();
        crate::studio::producer_migration::relocate_bot_checkpoint(&mut migrated, mapping)
            .map_err(conversion)?;
        checkpoint::write_representation(db, &original, &migrated)
            .await
            .map_err(conversion)
    }
}

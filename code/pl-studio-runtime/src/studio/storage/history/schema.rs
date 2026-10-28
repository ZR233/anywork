//! Official, ordered history migrations. Format numbers are only legacy import markers.
use super::*;
mod conversion;
pub(super) use conversion::{
    backfill_legacy_hidden_inputs as import_hidden_inputs,
    backfill_tool_user_input as import_tool_answers,
    migrate_context_sources as import_context_sources,
    migrate_unconsumed_input_bindings as import_input_bindings,
};
use conversion::{
    backfill_legacy_hidden_inputs, backfill_tool_user_input, migrate_context_sources,
    migrate_unconsumed_input_bindings,
};
use sea_orm_migration::{DbErr, MigrationName, MigrationTrait, MigratorTraitSelf, SchemaManager};
// The retained v2 codec is not the current target format.
const HISTORY_SCHEMA_VERSION: i64 = 9;

/// The fixed step lists of the two proven lineages.
///
/// A file belongs to exactly one lineage for its whole life. The lineage is chosen once from the
/// recorded facts and can only be extended by appending a step; it is never re-selected, reordered
/// or recomputed per release, and no step list is repaired to make a file look legal.
const MAIN_STEPS: &[&str] = &[
    "m20261026_000001_history_schema",
    "m20261026_000002_history_input_presentation",
    "m20261026_000003_history_input_bindings",
    "m20261026_000004_history_context_sources",
    "m20261026_000005_history_tool_answers",
    "m20261026_000006_history_checkpoint_v5",
    MODEL_ACCESS,
    EXECUTION_IDENTITY,
    PUBLIC_ARTIFACT,
];
/// A file that already declared the current format without any official record joins this lineage,
/// which records the takeover and nothing else: it never runs, records or replays the older
/// conversions. Later formats append their steps after the takeover.
const FORWARD_NINE_STEPS: &[&str] = &[ADOPT_NINE];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Lineage {
    Main,
    ForwardNine,
}

impl Lineage {
    fn steps(self) -> &'static [&'static str] {
        match self {
            Self::Main => MAIN_STEPS,
            Self::ForwardNine => FORWARD_NINE_STEPS,
        }
    }
}

struct MainMigrator {
    thread_id: String,
    execution_identity: Option<(
        pl_core::thread::ThreadCheckpoint,
        pl_core::thread::ThreadCheckpoint,
    )>,
}

impl MigratorTraitSelf for MainMigrator {
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
            Box::new(ModelAccess {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(ExecutionIdentity {
                thread_id: self.thread_id.clone(),
                candidate: self.execution_identity.clone(),
            }),
            Box::new(PublicArtifact),
        ]
    }
}

struct ForwardNineMigrator;

impl MigratorTraitSelf for ForwardNineMigrator {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        vec![Box::new(AdoptNine)]
    }
}

/// The main lineage for one call: the only place a migrator is built from a fixed list.
fn main_migrator(
    thread_id: &str,
    execution_identity: Option<(
        pl_core::thread::ThreadCheckpoint,
        pl_core::thread::ThreadCheckpoint,
    )>,
) -> MainMigrator {
    MainMigrator {
        thread_id: thread_id.to_owned(),
        execution_identity,
    }
}

fn is_prefix(applied: &[String], steps: &[&str]) -> bool {
    applied.len() <= steps.len()
        && applied
            .iter()
            .zip(steps.iter())
            .all(|(recorded, expected)| recorded == expected)
}

/// Chooses the one lineage this file belongs to from recorded facts only.
///
/// Both candidates are asked through the official read-only applied API: the official migrator
/// itself refuses a ledger whose recorded names are not in the list it is asked about, so a file
/// that matches neither list is refused instead of being forced into one. With an empty ledger the
/// declared format decides: a file that claims the current format (already verified against the
/// whole promised structure by the caller) cannot be a main file, because only the appended
/// conversion writes that number.
async fn select_lineage(
    db: &impl ConnectionTrait,
    declared_format: Option<i64>,
) -> Result<(Lineage, Vec<String>)> {
    let main = main_migrator("", None);
    match main.get_applied_migrations_read_only(db).await {
        Ok(applied) => {
            let names: Vec<String> = applied.iter().map(|step| step.name().to_owned()).collect();
            if names.is_empty() {
                return match declared_format {
                    Some(HISTORY_SCHEMA_VERSION) => Ok((Lineage::ForwardNine, names)),
                    _ => Ok((Lineage::Main, names)),
                };
            }
            ensure!(
                is_prefix(&names, Lineage::Main.steps()),
                "history migration records are not a legal prefix of the main sequence; existing data preserved"
            );
            Ok((Lineage::Main, names))
        }
        Err(main_error) => match ForwardNineMigrator
            .get_applied_migrations_read_only(db)
            .await
        {
            Ok(applied) => {
                let names: Vec<String> =
                    applied.iter().map(|step| step.name().to_owned()).collect();
                ensure!(
                    is_prefix(&names, Lineage::ForwardNine.steps()),
                    "history migration records are not a legal prefix of the forward-nine sequence; existing data preserved"
                );
                Ok((Lineage::ForwardNine, names))
            }
            Err(_) => Err(anyhow::Error::new(main_error).context(
                "history migration records match no proven lineage; existing data preserved",
            )),
        },
    }
}

/// Produces only the released structural prefix for source fixtures. Later model/identity source
/// facts use their real released migrator objects, not a retired lifecycle phase dispatcher.
#[cfg(test)]
async fn advance_source_schema<M: MigratorTraitSelf>(
    db: &DatabaseConnection,
    migrator: &M,
) -> Result<()> {
    let pending = migrator.get_pending_migrations_read_only(db).await?;
    let steps = pending
        .iter()
        .take_while(|step| step.name() < MODEL_ACCESS)
        .count();
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

/// Takes over a file that already declares the current format without any official record.
///
/// This is the first and, today, only step of its own lineage: it verifies everything the declared
/// format promises and changes nothing. It never runs, records or replays the older conversions, so
/// no checkpoint, instruction, model-access or execution-identity representation is rewritten and
/// no completion is claimed for work that this lineage cannot prove it performed. A file whose
/// structure does not satisfy the format is refused before any write.
struct AdoptNine;
impl MigrationName for AdoptNine {
    fn name(&self) -> &str {
        ADOPT_NINE
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for AdoptNine {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let current = version(manager.get_connection()).await?;
        if current != HISTORY_SCHEMA_VERSION {
            return Err(DbErr::Migration(format!(
                "forward-nine takeover found format {current}; existing data preserved"
            )));
        }
        verify_current_structure(manager).await
    }
}

const ADOPT_NINE: &str = "m20261026_000000_history_adopt_nine";
const MODEL_ACCESS: &str = "m20261026_000007_history_model_access";
pub(super) const EXECUTION_IDENTITY: &str = "m20261026_000008_history_execution_identity";
const PUBLIC_ARTIFACT: &str = "m20261026_000009_history_public_artifact";
/// The format this step owns. Later formats append their own step instead of editing this one.
const PUBLIC_ARTIFACT_FORMAT: i64 = 9;

/// Produces the old structural prefix for a source fixture. Production only uses these step
/// definitions in read-only lineage queries; the independent current Migrator writes targets.
#[cfg(test)]
pub(super) async fn initialize(db: &DatabaseConnection, thread_id: &str) -> Result<(String, i64)> {
    preflight(db, thread_id)
        .await
        .map_err(|error| crate::studio::startup::migration_error("history", "preflight", error))?;
    let (lineage, _) = select_lineage(db, declared_format(db).await?).await?;
    match lineage {
        Lineage::Main => advance_source_schema(db, &main_migrator(thread_id, None)).await?,
        Lineage::ForwardNine => advance_source_schema(db, &ForwardNineMigrator).await?,
    };
    read_identity(db).await
}

#[cfg(test)]
async fn read_identity(db: &DatabaseConnection) -> Result<(String, i64)> {
    let row = db
        .query_one_raw(statement(
            "SELECT database_id,schema_version FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("missing history identity after migration")?;
    Ok((
        row.try_get("", "database_id")?,
        row.try_get("", "schema_version")?,
    ))
}

/// The format the file itself declares, or `None` before its first schema exists.
async fn declared_format(db: &impl ConnectionTrait) -> Result<Option<i64>> {
    let meta = db
        .query_one_raw(statement(
            "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='history_meta'",
            vec![],
        ))
        .await?;
    if meta.is_none() {
        return Ok(None);
    }
    let Some(row) = db
        .query_one_raw(statement(
            "SELECT schema_version FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
    else {
        return Ok(None);
    };
    Ok(Some(row.try_get("", "schema_version")?))
}

pub(super) async fn preflight(db: &impl ConnectionTrait, thread_id: &str) -> Result<()> {
    // A pre-framework source may have no ledger. When one exists, hidden/generated authority
    // must be rejected before the framework interprets its recorded lineage.
    ordinary_columns(db, "seaql_migrations").await?;
    let meta = db
        .query_one_raw(statement(
            "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='history_meta'",
            vec![],
        ))
        .await?;
    if meta.is_none() {
        ensure!(db.query_one_raw(statement("SELECT 1 FROM sqlite_schema WHERE type='table' AND name NOT GLOB 'sqlite_*' AND name<>'seaql_migrations' LIMIT 1", vec![])).await?.is_none(),
            "unversioned nonempty history database; existing data preserved");
        ensure!(
            main_migrator("", None)
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
    // The ledger fixes the file's lineage for its whole life: the recorded names must be an ordered
    // prefix of exactly one proven step list, and the declared format must agree with that lineage.
    // Unknown, mixed, gapped or reordered records are refused before any write, with no second
    // runner and no hand-written completion.
    let (lineage, applied) = select_lineage(db, Some(version)).await?;
    match lineage {
        Lineage::Main => ensure!(
            version != HISTORY_SCHEMA_VERSION || applied.len() == MAIN_STEPS.len(),
            "history format claims the current number without its conversion; existing data preserved"
        ),
        Lineage::ForwardNine => ensure!(
            version == HISTORY_SCHEMA_VERSION,
            "forward-nine lineage must declare the current format; existing data preserved"
        ),
    }
    let pending = match lineage {
        Lineage::Main => {
            main_migrator(thread_id, None)
                .get_pending_migrations_read_only(db)
                .await?
        }
        Lineage::ForwardNine => {
            ForwardNineMigrator
                .get_pending_migrations_read_only(db)
                .await?
        }
    };
    ensure!(
        !pending.is_empty() || version == HISTORY_SCHEMA_VERSION,
        "history format conflicts with completed migrations; existing data preserved"
    );
    ensure!(
        row.try_get::<String>("", "thread_id")? == thread_id,
        "history database belongs to another Thread"
    );
    ensure!(
        !row.try_get::<String>("", "database_id")?.is_empty(),
        "history database identity is empty"
    );
    if version >= 8 {
        verify_structure(db).await?;
    }
    if db
        .query_one_raw(statement(
            "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='session_checkpoint'",
            vec![],
        ))
        .await?
        .is_some()
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
                (1..=5).contains(&checkpoint_version),
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

async fn version(db: &impl ConnectionTrait) -> Result<i64, DbErr> {
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

/// One column the current format promises: declared type, nullability, default and primary-key
/// order.
struct PromisedColumn {
    name: &'static str,
    kind: &'static str,
    not_null: bool,
    default: Option<&'static str>,
    /// 0 when the column is not part of the primary key, otherwise its 1-based position.
    primary_key: i64,
}

/// One named index the current format promises, with its ordered columns.
struct PromisedIndex {
    name: &'static str,
    columns: &'static [&'static str],
}

/// One table the current format promises, exactly as the create step declares it.
struct PromisedTable {
    name: &'static str,
    columns: &'static [PromisedColumn],
    indexes: &'static [PromisedIndex],
    /// Column sets some complete (non-partial) unique index must cover.
    unique: &'static [&'static [&'static str]],
}

pub(super) struct SourceFormat {
    pub(super) version: i64,
    pub(super) model_access_completed: bool,
    pub(super) execution_identity_completed: bool,
    pub(super) missing_input_columns: Vec<&'static str>,
}

pub(super) fn tables() -> impl Iterator<Item = &'static str> {
    PROMISED_STRUCTURE.iter().map(|table| table.name)
}

pub(super) fn columns(name: &str) -> Vec<(&'static str, &'static str)> {
    PROMISED_STRUCTURE
        .iter()
        .find(|table| table.name == name)
        .map(|table| {
            table
                .columns
                .iter()
                .map(|column| (column.name, column.kind))
                .collect()
        })
        .unwrap_or_default()
}

/// Frozen source shape: ten authoritative tables are mandatory. Only the two historically
/// additive input columns may be absent, and only before the published step that promised them.
pub(super) async fn source_format(
    db: &impl ConnectionTrait,
    thread_id: &str,
) -> Result<SourceFormat> {
    preflight(db, thread_id).await?;
    let version = declared_format(db)
        .await?
        .context("v2 source has no declared format")?;
    let (lineage, applied) = select_lineage(db, Some(version)).await?;
    let forward = lineage == Lineage::ForwardNine;
    for row in db.query_all_raw(statement(
        "SELECT type,name FROM sqlite_schema WHERE name NOT GLOB 'sqlite_*' AND type IN ('table','view','trigger')", vec![]
    )).await? {
        let name: String = row.try_get("", "name")?;
        ensure!(row.try_get::<String>("", "type")? == "table" &&
            (name == "seaql_migrations" || tables().any(|table| table == name)),
            "v2 source has an unknown authoritative schema object");
    }
    ensure!(
        db.query_one_raw(statement("PRAGMA foreign_key_check", vec![]))
            .await?
            .is_none(),
        "v2 source foreign key check failed"
    );
    if !forward {
        let minimum = match applied.len() {
            0 | 1 => 1,
            2 => 3,
            3 => 4,
            4 => 6,
            5..=8 => 8,
            _ => 9,
        };
        ensure!(
            version >= minimum,
            "v2 source format contradicts its completed official prefix"
        );
    }
    let mut missing = Vec::new();
    for table in PROMISED_STRUCTURE {
        let rows = ordinary_columns(db, table.name).await?;
        let mut actual = std::collections::BTreeMap::new();
        for row in rows {
            actual.insert(row.try_get::<String>("", "name")?, row);
        }
        ensure!(
            !actual.is_empty(),
            "v2 source table {} is absent",
            table.name
        );
        for promised in table.columns {
            let Some(row) = actual.remove(promised.name) else {
                let published_absence = table.name == "history_input_identities"
                    && !forward
                    && ((promised.name == "presentation" && version < 3 && applied.len() < 2)
                        || (promised.name == "request_digest"
                            && version < 8
                            && applied.is_empty()));
                ensure!(
                    published_absence,
                    "v2 source column {}.{} is absent without historical proof",
                    table.name,
                    promised.name
                );
                missing.push(promised.name);
                continue;
            };
            ensure!(
                row.try_get::<String>("", "type")?
                    .eq_ignore_ascii_case(promised.kind)
                    && (row.try_get::<i64>("", "notnull")? != 0) == promised.not_null
                    && row.try_get::<i64>("", "pk")? == promised.primary_key
                    && row.try_get::<Option<String>>("", "dflt_value")?.as_deref()
                        == promised.default,
                "v2 source column {}.{} has an unproven definition",
                table.name,
                promised.name
            );
        }
        ensure!(
            actual.is_empty(),
            "v2 source table {} has unknown columns",
            table.name
        );
        verify_unique(db, table).await?;
        verify_indexes(db, table).await?;
        if table.name == "history_input_identities" && missing.contains(&"presentation") {
            let canonical = canonical_statement("createtable", table.name)
                .context("missing frozen input table")?;
            let mut expected =
                check_expressions(canonical).context("invalid frozen input checks")?;
            expected.retain(|check| check != "presentationin('visible','hidden')");
            verify_checks_expected(db, table, expected).await?;
        } else {
            verify_checks(db, table).await?;
        }
        ensure!(
            db.query_all_raw(statement(
                &format!("PRAGMA foreign_key_list({})", table.name),
                vec![]
            ))
            .await?
            .is_empty(),
            "v2 source declares unexpected foreign keys in {}",
            table.name
        );
    }
    Ok(SourceFormat {
        version,
        model_access_completed: forward || applied.iter().any(|name| name == MODEL_ACCESS),
        execution_identity_completed: forward
            || applied.iter().any(|name| name == EXECUTION_IDENTITY),
        missing_input_columns: missing,
    })
}

const fn column(
    name: &'static str,
    kind: &'static str,
    not_null: bool,
    default: Option<&'static str>,
    pk: i64,
) -> PromisedColumn {
    PromisedColumn {
        name,
        kind,
        not_null,
        default,
        primary_key: pk,
    }
}

/// The complete structure this format promises, whoever wrote the file.
///
/// A file that declares a current format must satisfy every entry before any step reads its data,
/// which is why the takeover of a forward format verifies this instead of trusting the number: a
/// file whose tables only look current (a missing column, default, uniqueness, CHECK or index) is
/// refused instead of being silently completed by `CREATE TABLE IF NOT EXISTS`.
const PROMISED_STRUCTURE: &[PromisedTable] = &[
    PromisedTable {
        name: "history_meta",
        columns: &[
            column("id", "INTEGER", false, None, 1),
            column("schema_version", "INTEGER", true, None, 0),
            column("database_id", "TEXT", true, None, 0),
            column("thread_id", "TEXT", true, None, 0),
            column("applied_write_seq", "INTEGER", true, None, 0),
        ],
        indexes: &[],
        unique: &[],
    },
    PromisedTable {
        name: "history_items",
        columns: &[
            column("ordinal", "INTEGER", false, None, 1),
            column("item_id", "TEXT", true, None, 0),
            column("turn_id", "TEXT", true, None, 0),
            column("kind", "TEXT", true, None, 0),
            column("revision", "INTEGER", true, None, 0),
            column("lifecycle", "TEXT", true, None, 0),
            column("created_at", "INTEGER", true, None, 0),
            column("updated_at", "INTEGER", true, None, 0),
            column("payload", "TEXT", true, None, 0),
            column("last_write_seq", "INTEGER", true, None, 0),
        ],
        indexes: &[
            PromisedIndex {
                name: "history_items_by_turn",
                columns: &["turn_id", "ordinal"],
            },
            PromisedIndex {
                name: "history_items_by_kind_lifecycle",
                columns: &["kind", "lifecycle", "ordinal"],
            },
            PromisedIndex {
                name: "history_terminal_turns_by_write_seq",
                columns: &["last_write_seq", "ordinal"],
            },
            PromisedIndex {
                name: "history_items_by_kind",
                columns: &["kind", "ordinal"],
            },
        ],
        unique: &[&["item_id"]],
    },
    PromisedTable {
        name: "history_turns",
        columns: &[
            column("turn_id", "TEXT", false, None, 1),
            column("first_ordinal", "INTEGER", true, None, 0),
            column("last_ordinal", "INTEGER", true, None, 0),
            column("revision", "INTEGER", true, None, 0),
            column("payload", "TEXT", true, None, 0),
            column("last_write_seq", "INTEGER", true, None, 0),
        ],
        indexes: &[PromisedIndex {
            name: "history_turns_by_last_ordinal",
            columns: &["last_ordinal"],
        }],
        unique: &[&["turn_id"]],
    },
    PromisedTable {
        name: "history_input_identities",
        columns: &[
            column("item_id", "TEXT", false, None, 1),
            column("ordinal", "INTEGER", true, None, 0),
            column("revision", "INTEGER", true, None, 0),
            column("digest", "TEXT", true, None, 0),
            column("request_digest", "TEXT", false, None, 0),
            column("presentation", "TEXT", false, None, 0),
            column("payload", "TEXT", true, None, 0),
            column("last_write_seq", "INTEGER", true, None, 0),
        ],
        indexes: &[],
        unique: &[&["item_id"]],
    },
    PromisedTable {
        name: "history_fact_receipts",
        columns: &[
            column("item_id", "TEXT", true, None, 1),
            column("revision", "INTEGER", true, None, 2),
            column("kind", "TEXT", true, None, 0),
            column("digest", "TEXT", true, None, 0),
            column("payload", "TEXT", true, None, 0),
            column("last_write_seq", "INTEGER", true, None, 0),
        ],
        indexes: &[],
        unique: &[&["item_id", "revision"]],
    },
    PromisedTable {
        name: "history_message_identities",
        columns: &[
            column("message_id", "TEXT", false, None, 1),
            column("item_id", "TEXT", true, None, 0),
            column("sequence", "INTEGER", true, None, 0),
            column("digest", "TEXT", false, None, 0),
            column("last_write_seq", "INTEGER", true, None, 0),
        ],
        indexes: &[],
        unique: &[&["message_id"]],
    },
    PromisedTable {
        name: "session_checkpoint",
        columns: &[
            column("id", "INTEGER", false, None, 1),
            column("revision", "INTEGER", true, None, 0),
            column("context_revision", "INTEGER", true, None, 0),
            column("context_count", "INTEGER", true, None, 0),
            column("payload", "TEXT", true, None, 0),
            column("payload_hash", "TEXT", true, None, 0),
            column("legacy_cleanup", "INTEGER", true, Some("0"), 0),
        ],
        indexes: &[],
        unique: &[],
    },
    PromisedTable {
        name: "session_costs",
        columns: &[
            column("purpose", "TEXT", true, None, 1),
            column("currency", "TEXT", true, None, 2),
            column("amount", "REAL", true, None, 0),
        ],
        indexes: &[],
        unique: &[&["purpose", "currency"]],
    },
    PromisedTable {
        name: "current_context",
        columns: &[
            column("ordinal", "INTEGER", false, None, 1),
            column("record_id", "TEXT", true, None, 0),
            column("payload", "TEXT", true, None, 0),
            column("payload_hash", "TEXT", true, None, 0),
        ],
        indexes: &[],
        unique: &[&["record_id"]],
    },
    PromisedTable {
        name: "history_tool_tasks",
        columns: &[
            column("call_id", "TEXT", false, None, 1),
            column("revision", "INTEGER", true, None, 0),
            column("task_payload", "TEXT", true, None, 0),
            column("delivery_payload", "TEXT", false, None, 0),
            column("last_write_seq", "INTEGER", true, None, 0),
        ],
        indexes: &[],
        unique: &[&["call_id"]],
    },
];

fn structure_error(detail: String) -> DbErr {
    DbErr::Migration(format!("{detail}; existing data preserved"))
}

/// Removes SQL comments outside string literals, so commentary can neither add nor hide a promise.
fn strip_sql_comments(sql: &str) -> String {
    let characters: Vec<char> = sql.chars().collect();
    let mut kept = String::with_capacity(sql.len());
    let mut index = 0;
    while index < characters.len() {
        let current = characters[index];
        if current == '\'' {
            kept.push(current);
            index += 1;
            while index < characters.len() {
                kept.push(characters[index]);
                if characters[index] == '\'' {
                    index += 1;
                    break;
                }
                index += 1;
            }
            continue;
        }
        if current == '-' && characters.get(index + 1) == Some(&'-') {
            while index < characters.len() && characters[index] != '\n' {
                index += 1;
            }
            continue;
        }
        if current == '/' && characters.get(index + 1) == Some(&'*') {
            index += 2;
            while index + 1 < characters.len()
                && !(characters[index] == '*' && characters[index + 1] == '/')
            {
                index += 1;
            }
            index = (index + 2).min(characters.len());
            continue;
        }
        kept.push(current);
        index += 1;
    }
    kept
}

fn normalized_sql(sql: &str) -> String {
    strip_sql_comments(sql)
        .chars()
        .filter(|character| !character.is_whitespace())
        .collect::<String>()
        .to_ascii_lowercase()
}

/// SQLite stores a created object without `IF NOT EXISTS`, so both sides drop it before comparing.
fn normalized_object_sql(sql: &str) -> String {
    normalized_sql(sql).replace("ifnotexists", "")
}

/// The canonical statement of this format that declares `name`, if it declares one.
fn canonical_statement(prefix: &str, name: &str) -> Option<&'static str> {
    let wanted = format!("{prefix}{name}");
    SCHEMA_DDL.split(';').find(|statement| {
        // The object name must end here: a longer name that merely starts with it is another object.
        normalized_object_sql(statement)
            .strip_prefix(&wanted)
            .is_some_and(|rest| rest.starts_with('(') || rest.starts_with("on"))
    })
}

/// Every CHECK expression the given statement declares, comment- and literal-aware.
fn check_expressions(sql: &str) -> Option<Vec<String>> {
    let characters: Vec<char> = strip_sql_comments(sql).chars().collect();
    let mut found = Vec::new();
    let mut index = 0;
    while index < characters.len() {
        if characters[index] == '\'' {
            index += 1;
            while index < characters.len() {
                if characters[index] == '\'' {
                    index += 1;
                    break;
                }
                index += 1;
            }
            continue;
        }
        if matches_sql_word(&characters, index, "check") {
            let mut cursor = index + "check".len();
            while cursor < characters.len() && characters[cursor].is_whitespace() {
                cursor += 1;
            }
            if characters.get(cursor) == Some(&'(') {
                let (expression, next) = balanced_expression(&characters, cursor)?;
                found.push(expression);
                index = next;
                continue;
            }
        }
        index += 1;
    }
    found.sort();
    Some(found)
}

fn matches_sql_word(characters: &[char], start: usize, word: &str) -> bool {
    let end = start + word.chars().count();
    if end > characters.len() {
        return false;
    }
    let candidate: String = characters[start..end].iter().collect();
    candidate.eq_ignore_ascii_case(word)
        && !characters
            .get(end)
            .is_some_and(|next| next.is_alphanumeric() || *next == '_')
}

fn balanced_expression(characters: &[char], open: usize) -> Option<(String, usize)> {
    let mut depth = 0_u32;
    let mut index = open;
    while index < characters.len() {
        match characters[index] {
            '(' => depth += 1,
            ')' => {
                depth = depth.checked_sub(1)?;
                if depth == 0 {
                    let inside: String = characters[open + 1..index].iter().collect();
                    return Some((normalized_sql(&inside), index + 1));
                }
            }
            '\'' => {
                index += 1;
                while index < characters.len() && characters[index] != '\'' {
                    index += 1;
                }
            }
            _ => {}
        }
        index += 1;
    }
    None
}

/// Verifies the whole promised structure read-only, before any step has written anything.
async fn verify_current_structure(manager: &SchemaManager<'_>) -> Result<(), DbErr> {
    verify_structure(manager.get_connection()).await
}

pub(super) async fn verify_structure(db: &impl ConnectionTrait) -> Result<(), DbErr> {
    for table in PROMISED_STRUCTURE {
        if db
            .query_one_raw(statement(
                "SELECT 1 FROM sqlite_schema WHERE type='table' AND name=?",
                vec![table.name.into()],
            ))
            .await?
            .is_none()
        {
            return Err(structure_error(format!(
                "current history table {} is missing",
                table.name
            )));
        }
        verify_columns(db, table).await?;
        verify_unique(db, table).await?;
        verify_indexes(db, table).await?;
        verify_checks(db, table).await?;
        let foreign_keys = db
            .query_all_raw(statement(
                &format!("PRAGMA foreign_key_list({})", table.name),
                vec![],
            ))
            .await?;
        if !foreign_keys.is_empty() {
            return Err(structure_error(format!(
                "current history table {} declares an unexpected foreign key",
                table.name
            )));
        }
    }
    Ok(())
}

/// Bounded catalog check for current readiness, shared with the full import validator. Optional
/// nonunique indexes are not authority; unknown tables, views and triggers are not accepted.
pub(super) async fn verify_authoritative_objects(db: &impl ConnectionTrait) -> Result<(), DbErr> {
    let mut allowed = tables().map(Into::into).collect::<Vec<sea_orm::Value>>();
    allowed.push("seaql_migrations".into());
    let placeholders = vec!["?"; allowed.len()].join(",");
    if db
        .query_one_raw(statement(
            &format!(
                "SELECT 1 FROM sqlite_schema WHERE name NOT GLOB 'sqlite_*' AND \
         (type IN ('trigger','view') OR (type='table' AND name NOT IN ({placeholders}))) LIMIT 1"
            ),
            allowed,
        ))
        .await?
        .is_some()
    {
        return Err(structure_error(
            "history contains an unknown authoritative schema object".into(),
        ));
    }
    Ok(())
}

/// All registered history fields are ordinary stored columns. table_info omits hidden/generated
/// columns entirely; xinfo enumerates them, including generated fields with a required name and
/// otherwise matching type/nullability. Never filter them out before checking the full column set.
async fn ordinary_columns(
    db: &impl ConnectionTrait,
    table: &str,
) -> Result<Vec<sea_orm::QueryResult>, DbErr> {
    let rows = db
        .query_all_raw(statement(&format!("PRAGMA table_xinfo({table})"), vec![]))
        .await?;
    for row in &rows {
        if row.try_get::<i64>("", "hidden")? != 0 {
            return Err(structure_error(format!(
                "history table {table} declares hidden or generated columns"
            )));
        }
    }
    Ok(rows)
}

async fn verify_columns(db: &impl ConnectionTrait, table: &PromisedTable) -> Result<(), DbErr> {
    let rows = ordinary_columns(db, table.name).await?;
    if rows.len() != table.columns.len() {
        return Err(structure_error(format!(
            "current history table {} has {} columns instead of {}",
            table.name,
            rows.len(),
            table.columns.len()
        )));
    }
    for promised in table.columns {
        let row = rows
            .iter()
            .find(|row| row.try_get::<String>("", "name").ok().as_deref() == Some(promised.name))
            .ok_or_else(|| {
                structure_error(format!(
                    "current history column {}.{} is missing",
                    table.name, promised.name
                ))
            })?;
        let name: String = row.try_get("", "name")?;
        let kind: String = row.try_get("", "type")?;
        let not_null: i64 = row.try_get("", "notnull")?;
        let default: Option<String> = row.try_get("", "dflt_value")?;
        let primary_key: i64 = row.try_get("", "pk")?;
        if name != promised.name
            || !kind.eq_ignore_ascii_case(promised.kind)
            || (not_null != 0) != promised.not_null
            || default.as_deref() != promised.default
            || primary_key != promised.primary_key
        {
            return Err(structure_error(format!(
                "current history column {}.{} does not match the promised definition",
                table.name, promised.name
            )));
        }
    }
    Ok(())
}

async fn verify_unique(db: &impl ConnectionTrait, table: &PromisedTable) -> Result<(), DbErr> {
    let mut covered: Vec<Vec<String>> = Vec::new();
    for row in db
        .query_all_raw(statement(
            &format!(
                "SELECT name,partial FROM pragma_index_list(?) WHERE [unique]<>0 LIMIT {}",
                table.unique.len() + 1
            ),
            vec![table.name.into()],
        ))
        .await?
    {
        let index: String = row.try_get("", "name")?;
        let unexpected = || {
            structure_error(format!(
                "current history table {} declares an unregistered unique constraint ({index})",
                table.name
            ))
        };
        if row.try_get::<i64>("", "partial")? != 0 {
            return Err(unexpected());
        }
        let key_limit = table.unique.iter().map(|key| key.len()).max().unwrap_or(0) + 1;
        let keys = db.query_all_raw(statement(
            &format!("SELECT cid,name,[desc],coll FROM pragma_index_xinfo(?) WHERE [key]=1 ORDER BY seqno LIMIT {key_limit}"),
            vec![index.clone().into()],
        )).await?;
        let mut columns = Vec::new();
        for key in keys {
            // Expressions, descending keys and non-BINARY collations can reject different writes
            // despite naming the same columns. They are not the published uniqueness contract.
            if key.try_get::<i64>("", "cid")? < 0
                || key.try_get::<i64>("", "desc")? != 0
                || key.try_get::<Option<String>>("", "coll")?.as_deref() != Some("BINARY")
            {
                return Err(unexpected());
            }
            let Some(name) = key.try_get::<Option<String>>("", "name")? else {
                return Err(unexpected());
            };
            columns.push(name);
        }
        if !table.unique.iter().any(|expected| {
            columns
                .iter()
                .map(String::as_str)
                .eq(expected.iter().copied())
        }) || covered.contains(&columns)
        {
            return Err(unexpected());
        }
        covered.push(columns);
    }
    for promised in table.unique {
        let expected: Vec<String> = promised.iter().map(|column| (*column).to_owned()).collect();
        if !covered.contains(&expected) {
            return Err(structure_error(format!(
                "current history table {} is missing the unique constraint on ({})",
                table.name,
                expected.join(", ")
            )));
        }
    }
    Ok(())
}

/// The framework owns this table, but an extra constraint can still block its future official
/// writes. Target readiness checks its published version PK without imposing a ledger on old
/// pre-framework sources (which legitimately have no migration table).
pub(super) async fn verify_target_migration_uniqueness(
    db: &impl ConnectionTrait,
) -> Result<(), DbErr> {
    const TABLE: PromisedTable = PromisedTable {
        name: "seaql_migrations",
        columns: &[],
        indexes: &[],
        unique: &[&["version"]],
    };
    ordinary_columns(db, TABLE.name).await?;
    verify_unique(db, &TABLE).await
}

async fn verify_indexes(db: &impl ConnectionTrait, table: &PromisedTable) -> Result<(), DbErr> {
    for promised in table.indexes {
        let row = db
            .query_one_raw(statement(
                "SELECT sql FROM sqlite_schema WHERE type='index' AND name=?",
                vec![promised.name.to_owned().into()],
            ))
            .await?
            .ok_or_else(|| {
                structure_error(format!(
                    "current history index {} is missing",
                    promised.name
                ))
            })?;
        // The whole definition is compared, so a partial index with a different predicate (for
        // example `WHERE 0`) cannot stand in for the promised one.
        let stored: Option<String> = row.try_get("", "sql")?;
        let stored = stored.ok_or_else(|| {
            structure_error(format!(
                "current history index {} has no stored definition",
                promised.name
            ))
        })?;
        let canonical = canonical_statement("createindex", promised.name).ok_or_else(|| {
            structure_error(format!(
                "canonical definition of index {} is missing",
                promised.name
            ))
        })?;
        if normalized_object_sql(&stored) != normalized_object_sql(canonical) {
            return Err(structure_error(format!(
                "current history index {} does not match the promised definition",
                promised.name
            )));
        }
        let expected: Vec<String> = promised
            .columns
            .iter()
            .map(|column| (*column).to_owned())
            .collect();
        if index_columns(db, promised.name).await?.as_ref() != Some(&expected) {
            return Err(structure_error(format!(
                "current history index {} does not cover ({})",
                promised.name,
                expected.join(", ")
            )));
        }
    }
    Ok(())
}

/// Returns an index's ordered columns, or `None` when it is an expression index or its name cannot
/// be used as a literal pragma argument.
async fn index_columns(
    db: &impl ConnectionTrait,
    index: &str,
) -> Result<Option<Vec<String>>, DbErr> {
    if index.contains('\'') || index.contains('"') || index.contains(')') {
        return Ok(None);
    }
    let mut columns = Vec::new();
    for row in db
        .query_all_raw(statement(&format!("PRAGMA index_info({index})"), vec![]))
        .await?
    {
        let Some(name) = row.try_get::<Option<String>>("", "name")? else {
            return Ok(None);
        };
        columns.push(name);
    }
    Ok(Some(columns))
}

/// Compares the real CHECK expressions of a table with the ones this format declares.
async fn verify_checks(db: &impl ConnectionTrait, table: &PromisedTable) -> Result<(), DbErr> {
    let canonical = canonical_statement("createtable", table.name).ok_or_else(|| {
        structure_error(format!(
            "canonical definition of table {} is missing",
            table.name
        ))
    })?;
    let expected = check_expressions(canonical).ok_or_else(|| {
        structure_error(format!(
            "canonical constraints of table {} cannot be read",
            table.name
        ))
    })?;
    verify_checks_expected(db, table, expected).await
}

async fn verify_checks_expected(
    db: &impl ConnectionTrait,
    table: &PromisedTable,
    expected: Vec<String>,
) -> Result<(), DbErr> {
    let row = db
        .query_one_raw(statement(
            "SELECT sql FROM sqlite_schema WHERE type='table' AND name=?",
            vec![table.name.to_owned().into()],
        ))
        .await?
        .ok_or_else(|| {
            structure_error(format!(
                "current history table {} has no stored definition",
                table.name
            ))
        })?;
    let stored: String = row.try_get("", "sql")?;
    let actual = check_expressions(&stored).ok_or_else(|| {
        structure_error(format!(
            "stored constraints of table {} cannot be read",
            table.name
        ))
    })?;
    if actual != expected {
        return Err(structure_error(format!(
            "current history table {} does not declare the promised constraints",
            table.name
        )));
    }
    Ok(())
}

/// The canonical structure this format creates, applied by the create step and reused as the
/// only source of truth for what a current file must contain. Commentary is never part of the
/// structure a file has to prove.
pub(super) const SCHEMA_DDL: &str = "CREATE TABLE IF NOT EXISTS history_meta (
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
        );";

/// The eight steps the previous build published, available to tests only.
///
/// A test that needs a real main-eight file runs exactly these step objects through the same
/// official migrator, in the same order, instead of hand-writing completion records or copying a
/// second runner. Production uses [`MAIN_STEPS`] and [`FORWARD_NINE_STEPS`] only to recognize
/// the read-only source lineage; the independent current-history Migrator owns target writes.
#[cfg(test)]
struct ReleasedEightMigrator {
    thread_id: String,
    candidate: Option<(
        pl_core::thread::ThreadCheckpoint,
        pl_core::thread::ThreadCheckpoint,
    )>,
}

#[cfg(test)]
impl MigratorTraitSelf for ReleasedEightMigrator {
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
            Box::new(ModelAccess {
                thread_id: self.thread_id.clone(),
            }),
            Box::new(ExecutionIdentity {
                thread_id: self.thread_id.clone(),
                candidate: self.candidate.clone(),
            }),
        ]
    }
}

/// Advances the released eight-step sequence the way the previous build did: without a checkpoint it
/// stops before the execution-identity step, and with one it completes that step.
#[cfg(test)]
pub(super) async fn advance_released_eight(
    db: &DatabaseConnection,
    thread_id: &str,
    candidate: Option<(
        pl_core::thread::ThreadCheckpoint,
        pl_core::thread::ThreadCheckpoint,
    )>,
) -> Result<()> {
    let migrator = ReleasedEightMigrator {
        thread_id: thread_id.to_owned(),
        candidate: candidate.clone(),
    };
    let pending = migrator.get_pending_migrations_read_only(db).await?;
    let steps = if candidate.is_none() {
        pending
            .iter()
            .take_while(|step| step.name() != EXECUTION_IDENTITY)
            .count()
    } else {
        pending.len()
    };
    migrator.up(db, Some(u32::try_from(steps)?)).await?;
    Ok(())
}

/// Generates the old producer's empty schema, not an import progress record. Subsequent fixture
/// facts are written as ordinary source commits; target migration still runs independently.
#[cfg(test)]
pub(super) async fn create_released_source(db: &DatabaseConnection, thread_id: &str) -> Result<()> {
    main_migrator(thread_id, None).up(db, Some(1)).await?;
    Ok(())
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
        db.execute_unprepared(SCHEMA_DDL).await?;

        if !manager
            .has_column("history_input_identities", "request_digest")
            .await?
        {
            db.execute_unprepared(
                "ALTER TABLE history_input_identities ADD COLUMN request_digest TEXT",
            )
            .await?;
        }
        // A file created here reaches the tool-answer format: that is what its structure plus the
        // data steps of the structure prefix produce, and it never overwrites an existing row. The
        // public-artifact format is appended by its own step, exactly like every earlier format, so
        // a new file is advanced by the same named conversion instead of being pre-declared newer.
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

struct ExecutionIdentity {
    thread_id: String,
    candidate: Option<(
        pl_core::thread::ThreadCheckpoint,
        pl_core::thread::ThreadCheckpoint,
    )>,
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
        let db = manager.get_connection();
        let stored = checkpoint::read(db, &self.thread_id)
            .await
            .map_err(conversion)?;
        let (original, migrated) = match (&self.candidate, &stored) {
            (Some((original, migrated)), _) => (original, migrated),
            (None, _) => {
                return Err(DbErr::Migration(
                    "execution identity requires explicit recovery preparation".into(),
                ));
            }
        };
        let current =
            stored.ok_or_else(|| DbErr::Migration("recovery checkpoint is absent".into()))?;
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

/// Format 9 admits explicit public-artifact items.
///
/// Nothing is rewritten: an archived file is not retroactively a publication, and existing
/// payloads, resource references and checkpoint envelopes stay byte-identical. The step is still a
/// named, recorded conversion because a new file format is declared by an ordered step that owns
/// it, never by skipping the change when no table is altered. It is also the named takeover entry
/// for a file that already declares this format without official completion records: such a file
/// must satisfy the current structure exactly, and its number is never lowered to an earlier
/// step's value.
struct PublicArtifact;
impl MigrationName for PublicArtifact {
    fn name(&self) -> &str {
        PUBLIC_ARTIFACT
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for PublicArtifact {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let db = manager.get_connection();
        let current = version(db).await?;
        if current == PUBLIC_ARTIFACT_FORMAT {
            // A forward format takes over only when it really holds the structures its number
            // promises; the completion record below is then the first official proof of lineage.
            return verify_current_structure(manager).await;
        }
        if current != PUBLIC_ARTIFACT_FORMAT - 1 {
            return Err(DbErr::Migration(format!(
                "history format {current} cannot advance to {PUBLIC_ARTIFACT_FORMAT}; existing data preserved"
            )));
        }
        verify_current_structure(manager).await?;
        // The format marker, the conversion it stands for and this step's completion record commit
        // in one framework transaction; a concurrent change keeps the original data and fails.
        let advanced = db
            .execute_raw(statement(
                "UPDATE history_meta SET schema_version=? WHERE id=1 AND schema_version=?",
                vec![
                    PUBLIC_ARTIFACT_FORMAT.into(),
                    (PUBLIC_ARTIFACT_FORMAT - 1).into(),
                ],
            ))
            .await?;
        if advanced.rows_affected() != 1 {
            return Err(DbErr::Migration(
                "history format changed during its public-artifact step; existing data preserved"
                    .into(),
            ));
        }
        Ok(())
    }
}

#[cfg(test)]
mod structure_tests {
    use super::*;
    use sea_orm::Database;

    async fn memory() -> DatabaseConnection {
        Database::connect("sqlite::memory:")
            .await
            .expect("memory history")
    }

    #[tokio::test]
    async fn released_identity_step_requires_a_real_checkpoint_candidate() -> anyhow::Result<()> {
        let db = memory().await;
        let migrator = main_migrator("strict-source", None);
        migrator.up(&db, Some(7)).await?;
        assert!(migrator.up(&db, None).await.is_err());
        let applied = migrator.get_applied_migrations_read_only(&db).await?;
        assert_eq!(applied.len(), 7);
        assert!(!applied.iter().any(|step| step.name() == EXECUTION_IDENTITY));
        Ok(())
    }

    async fn file_database(path: &std::path::Path) -> anyhow::Result<DatabaseConnection> {
        Ok(Database::connect(
            crate::studio::paths::sqlite_file_options(
                path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?)
    }

    const PROBE_COLUMNS: &[PromisedColumn] = &[column("id", "TEXT", true, None, 0)];
    const PROBE_UNIQUE: &[&[&str]] = &[&["id"]];
    const PROBE_FLAG_COLUMNS: &[PromisedColumn] = &[
        column("id", "INTEGER", false, None, 1),
        column("flag", "INTEGER", true, Some("0"), 0),
    ];

    /// The canonical structure itself always passes, which is what proves main's real source.
    #[tokio::test]
    async fn canonical_structure_passes() -> anyhow::Result<()> {
        let db = memory().await;
        db.execute_unprepared(SCHEMA_DDL).await?;
        verify_current_structure(&SchemaManager::new(&db)).await?;
        Ok(())
    }

    /// A comment that merely quotes a constraint never counts as one.
    #[tokio::test]
    async fn comment_quoted_constraint_is_not_a_constraint() -> anyhow::Result<()> {
        // A schema text edit needs its own connection, so this proof uses a file-backed history.
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        {
            let db = file_database(&path).await?;
            db.execute_unprepared(SCHEMA_DDL).await?;
            db.close().await?;
        }
        {
            let db = file_database(&path).await?;
            db.execute_unprepared(
                "PRAGMA writable_schema=ON; \
                 UPDATE sqlite_schema SET sql=replace(sql,'CHECK (json_valid(payload))', \
                   '/* CHECK (json_valid(payload)) */ CHECK (1)') WHERE name='history_items'; \
                 PRAGMA writable_schema=OFF;",
            )
            .await?;
            db.close().await?;
        }
        let db = file_database(&path).await?;
        let error = verify_current_structure(&SchemaManager::new(&db))
            .await
            .expect_err("a comment must not stand in for the real constraint");
        assert!(format!("{error}").contains("constraints"), "{error}");
        db.close().await?;
        Ok(())
    }

    /// A partial unique index never constrains the whole column set.
    #[tokio::test]
    async fn partial_unique_index_does_not_satisfy_the_promise() -> anyhow::Result<()> {
        let db = memory().await;
        db.execute_unprepared(
            "CREATE TABLE probe (id TEXT NOT NULL, b TEXT NOT NULL);
             CREATE UNIQUE INDEX probe_unique ON probe(id) WHERE 0;",
        )
        .await?;
        let table = PromisedTable {
            name: "probe",
            columns: PROBE_COLUMNS,
            indexes: &[],
            unique: PROBE_UNIQUE,
        };
        assert!(
            verify_unique(&db, &table).await.is_err(),
            "a partial unique index must not prove completeness"
        );
        Ok(())
    }

    /// A partial index with another predicate is a different index.
    #[tokio::test]
    async fn partial_index_with_another_predicate_is_refused() -> anyhow::Result<()> {
        let db = memory().await;
        db.execute_unprepared(SCHEMA_DDL).await?;
        db.execute_unprepared(
            "DROP INDEX history_terminal_turns_by_write_seq;
             CREATE INDEX history_terminal_turns_by_write_seq
                ON history_items(last_write_seq, ordinal) WHERE 0;",
        )
        .await?;
        let table = PROMISED_STRUCTURE
            .iter()
            .find(|table| table.name == "history_items")
            .expect("items table");
        let error = verify_indexes(&db, table)
            .await
            .expect_err("a different predicate must be refused");
        assert!(format!("{error}").contains("history_terminal_turns_by_write_seq"));
        Ok(())
    }

    /// A column default is part of the structure, not a formatting detail.
    #[tokio::test]
    async fn column_default_is_compared() -> anyhow::Result<()> {
        let db = memory().await;
        db.execute_unprepared(
            "CREATE TABLE probe (id INTEGER PRIMARY KEY, flag INTEGER NOT NULL DEFAULT 1);",
        )
        .await?;
        let table = PromisedTable {
            name: "probe",
            columns: PROBE_FLAG_COLUMNS,
            indexes: &[],
            unique: &[],
        };
        assert!(
            verify_columns(&db, &table).await.is_err(),
            "a different default must be refused"
        );
        Ok(())
    }
}

#[cfg(test)]
mod lineage_tests {
    use super::*;
    use crate::studio::storage::history::{HistoryInitialization, HistoryStore};
    use pl_core::thread::{ThreadCheckpoint, ThreadSnapshot};
    use sea_orm::Database;
    use std::collections::BTreeMap;

    async fn file_database(path: &std::path::Path) -> anyhow::Result<DatabaseConnection> {
        Ok(Database::connect(
            crate::studio::paths::sqlite_file_options(
                path,
                crate::studio::paths::SqliteFileMode::Create,
                |options| options,
            )
            .await?,
        )
        .await?)
    }

    async fn recorded(db: &impl ConnectionTrait) -> anyhow::Result<Vec<String>> {
        Ok(db
            .query_all_raw(statement(
                "SELECT version FROM seaql_migrations ORDER BY applied_at,version",
                vec![],
            ))
            .await?
            .iter()
            .map(|row| row.try_get::<String>("", "version"))
            .collect::<Result<Vec<_>, _>>()?)
    }

    /// A file the previous build really produced — its own eight steps run through the same official
    /// migrator against a real checkpoint — imports without losing payload, checkpoint or its
    /// original lineup. The new target records only the step it really performed.
    #[tokio::test]
    async fn released_eight_file_upgrades_to_the_public_artifact_format() -> anyhow::Result<()> {
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("history.sqlite");
        let thread_id = "released-provenance";

        // The previous build created the file and advanced it to the tool-answer format.
        {
            let db = file_database(&path).await?;
            advance_released_eight(&db, thread_id, None).await?;
            db.close().await?;
        }

        // It then committed a real checkpoint, which the current writer must not disturb.
        let source = file_database(&path).await?;
        let checkout = ThreadCheckpoint::capture(
            thread_id.into(),
            1,
            ThreadSnapshot {
                commit_sequence: 1,
                extensions: BTreeMap::from([(
                    "vendor.unknown".into(),
                    pl_core::thread::extensions::ExtensionRecord {
                        revision: 6,
                        payload: pl_core::context::OpaquePayload::new(
                            "vendor.unknown",
                            7,
                            "opaque bytes must survive",
                        )?,
                    },
                )]),
                ..Default::default()
            },
        );
        let tx = begin_write(&source).await?;
        checkpoint::write(&tx, &checkout, None).await?;
        tx.execute_unprepared("UPDATE history_meta SET applied_write_seq=1 WHERE id=1")
            .await?;
        tx.commit().await?;

        // The previous build finished its last published step with the verified pre-image.
        let original = checkpoint::read(&source, thread_id)
            .await?
            .context("saved checkpoint")?;
        {
            let db = &source;
            advance_released_eight(db, thread_id, Some((original.clone(), original.clone())))
                .await?;
            assert_eq!(
                declared_format(db).await?,
                Some(8),
                "a main-eight file keeps its own format until the appended step runs"
            );
            assert_eq!(recorded(db).await?, MAIN_STEPS[..8].to_vec());
        }
        let preserved = serde_json::to_vec(&original)?;
        let target = directory.path().join("history-current.sqlite");
        let upgraded = HistoryStore::open(&target, thread_id).await?;
        upgraded
            .initialize(HistoryInitialization::ImportV2 {
                source_database: path.clone(),
                legacy_state: crate::studio::storage::state::StateStore::new(
                    directory.path().to_owned(),
                    thread_id,
                ),
                migrate_execution_identity: std::sync::Arc::new(|_| {
                    anyhow::bail!("released m8 cannot be replayed")
                }),
            })
            .await?;
        upgraded.prepare_activation().await?;
        let db = upgraded.writer().await?.db.clone();
        assert_eq!(
            declared_format(&db).await?,
            Some(super::super::HISTORY_SCHEMA_VERSION)
        );
        assert_eq!(recorded(&source).await?, MAIN_STEPS[..8].to_vec());
        assert_eq!(
            recorded(&db).await?,
            vec![super::super::current::CURRENT_STEP]
        );
        let migrated = upgraded
            .checkpoint()
            .await?
            .context("upgraded checkpoint")?;
        assert_eq!(
            serde_json::to_vec(&migrated)?,
            preserved,
            "the format step rewrites no checkpoint bytes"
        );
        assert_eq!(
            migrated.state.extensions["vendor.unknown"]
                .payload
                .content(),
            "opaque bytes must survive"
        );
        source.close().await?;
        Ok(())
    }
}

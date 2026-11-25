//! Frozen schema-24 storage for one-shot v2 TOML import and schema 24→25 migration.

use super::sqlite_util::is_retryable_write;
use std::{
    path::{Path, PathBuf},
    time::Duration,
};

use anyhow::{Context, Result, ensure};
use sea_orm::sqlx::sqlite::{SqliteJournalMode, SqliteSynchronous};
use sea_orm::{
    ConnectionTrait, Database, DatabaseBackend, DatabaseConnection, SqliteTransactionMode,
    Statement, TransactionOptions, TransactionTrait, Value,
};

const HISTORY_SCHEMA_VERSION: i64 = 24;

pub(in crate::studio) mod conversation;
pub(in crate::studio) mod execution_lifecycle;
pub(in crate::studio) mod execution_sources;
pub(in crate::studio) mod turns;

mod checkpoint;

mod producer;
pub(crate) mod schema;
mod timeline;
pub(crate) use schema::validate_layout_source;

#[cfg(test)]
pub(crate) fn frozen_v24_migrations(
    thread_id: &str,
) -> Vec<Box<dyn sea_orm_migration::MigrationTrait>> {
    schema::migrations_for_upgrade(thread_id)
}

/// Frozen schema-24 source handle used by the one-shot upgrade and migration fixtures.
///
/// New Threads never create this store and normal reads never use it. The live schema-25
/// `crate::history::HistoryStore` owns production History; this handle remains only while explicit
/// v2 TOML import, schema 24→25 backup/conversion, and their focused regression fixtures run.
#[derive(Clone)]
pub(crate) struct HistoryStore {
    state: std::sync::Arc<HistoryStoreState>,
}

struct HistoryStoreState {
    closed: std::sync::atomic::AtomicBool,
    path: PathBuf,
    thread_id: String,
    /// The single writer connection, opened on the first write.
    ///
    /// Effect batches use one connection for short single-writer transactions. The Session owns
    /// ordinal allocation; this connection only persists the ordinals it supplies.
    writer: tokio::sync::OnceCell<HistoryConnection>,
    /// A read-only connection to an *existing* database, opened on the first cold read.
    reader: tokio::sync::OnceCell<HistoryConnection>,
    /// Serializes the first writer initialization against every cold read-only open.
    ///
    /// The writer's `connect(mode=rwc)` creates the file before `initialize` commits the schema and
    /// the identity row, so a read that observed the file inside that window would validate a
    /// half-initialized database and fail closed on a store that is merely still being created. The
    /// writer therefore holds the write side for its whole connect+initialize, while every cold open
    /// takes the read side first: a reader runs either before the file exists (an empty history) or
    /// after the database is fully initialized. Every read uses the independent read-only pool.
    init: tokio::sync::RwLock<()>,
}

/// One live connection plus the database identity it validated.
struct HistoryConnection {
    db: DatabaseConnection,
    database_id: String,
    schema_version: i64,
}

/// One receipt write that must land in the same transaction as the effect that produced it.
pub(crate) struct FactReceiptWrite {
    pub item_id: String,
    pub revision: u64,
    pub kind: &'static str,
    pub payload: String,
}

impl std::fmt::Debug for HistoryStore {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("HistoryStore")
            .field("thread_id", &self.state.thread_id)
            .finish_non_exhaustive()
    }
}

impl HistoryStore {
    /// Binds one Thread history database path without touching the filesystem or database.
    ///
    /// The first write creates the directory/database and initializes/upgrades the schema; reads
    /// only ever observe an existing database (or an explicitly empty history) and never mutate a
    /// byte, so an absent or damaged store cannot be resurrected by pagination or `read_item`.
    pub(crate) async fn open(path: &Path, thread_id: &str) -> Result<Self> {
        ensure!(
            !thread_id.is_empty(),
            "history Thread identity must not be empty"
        );
        Ok(Self {
            state: std::sync::Arc::new(HistoryStoreState {
                closed: std::sync::atomic::AtomicBool::new(false),
                path: path.to_owned(),
                thread_id: thread_id.to_owned(),
                writer: tokio::sync::OnceCell::new(),
                reader: tokio::sync::OnceCell::new(),
                init: tokio::sync::RwLock::new(()),
            }),
        })
    }

    pub(crate) fn thread_id(&self) -> &str {
        &self.state.thread_id
    }

    /// The lifecycle owner first drains producers, then revokes both original pools.
    pub(in crate::studio) async fn close_for_deletion(&self) -> Result<()> {
        let _initializing = self.state.init.write().await;
        self.state
            .closed
            .store(true, std::sync::atomic::Ordering::Release);
        if let Some(reader) = self.state.reader.get() {
            reader.db.close_by_ref().await?;
        }
        if let Some(writer) = self.state.writer.get() {
            writer.db.close_by_ref().await?;
        }
        Ok(())
    }

    /// The connection cold reads use, or `None` when no history database exists yet.
    ///
    /// The existing file is opened by an independent read-only pool, including while the writer is
    /// alive. A missing file is reported as an empty history and is never created here, so a cold
    /// read leaves an absent store absent. A read that races the first
    /// writer initialization waits behind it instead of validating the half-initialized database
    /// that `connect(mode=rwc)` just created.
    async fn reader(&self) -> Result<Option<&HistoryConnection>> {
        // The first writer may have created the file with `connect(mode=rwc)` while its schema and
        // identity are still uncommitted. Take the read side of the initialization lock before
        // touching the file, so we either run before the file exists or after it is fully
        // initialized; never against a half-initialized database.
        let _initializing = self.state.init.read().await;
        if let Some(writer) = self.state.writer.get() {
            ensure!(
                writer.schema_version == HISTORY_SCHEMA_VERSION,
                "history requires explicit storage preparation"
            );
        }
        self.read_only_connection().await
    }

    /// Caller holds the initialization read guard. Never returns the writer, even when another
    /// observer keeps it alive; a missing file remains missing instead of reading an unlinked DB.
    async fn read_only_connection(&self) -> Result<Option<&HistoryConnection>> {
        ensure!(
            !self.state.closed.load(std::sync::atomic::Ordering::Acquire),
            "history is permanently closed"
        );
        if !tokio::fs::try_exists(&self.state.path).await? {
            return Ok(None);
        }
        let reader = self
            .state
            .reader
            .get_or_try_init(|| async {
                let db = connect_read_only(&self.state.path).await?;
                schema::validate_identity_collations(&db).await?;
                let (database_id, schema_version) =
                    validate_existing(&db, &self.state.thread_id).await?;
                Ok::<HistoryConnection, anyhow::Error>(HistoryConnection {
                    db,
                    database_id,
                    schema_version,
                })
            })
            .await?;
        if let Some(writer) = self.state.writer.get() {
            ensure!(
                reader.database_id == writer.database_id,
                "read-only history does not match the shared writer identity"
            );
        }
        Ok(Some(reader))
    }

    /// The single writer connection, created and upgraded on first use.
    ///
    /// The whole first connect+initialize runs under the write side of the initialization lock, so a
    /// cold read that races it cannot observe the created-but-uninitialized database. The guard is
    /// released as soon as the connection is published, and every later call returns through the
    /// fast path above it.
    async fn writer(&self) -> Result<&HistoryConnection> {
        self.open_writer(crate::studio::paths::SqliteFileMode::Create)
            .await?
            .context("history writer was not initialized")
    }

    async fn open_writer(
        &self,
        mode: crate::studio::paths::SqliteFileMode,
    ) -> Result<Option<&HistoryConnection>> {
        ensure!(
            !self.state.closed.load(std::sync::atomic::Ordering::Acquire),
            "history is permanently closed"
        );
        if let Some(writer) = self.state.writer.get() {
            return Ok(Some(writer));
        }
        let _initializing = self.state.init.write().await;
        ensure!(
            !self.state.closed.load(std::sync::atomic::Ordering::Acquire),
            "history is permanently closed"
        );
        if matches!(mode, crate::studio::paths::SqliteFileMode::ReadWrite)
            && !tokio::fs::try_exists(&self.state.path).await?
        {
            return Ok(None);
        }
        // First-connect migration state belongs only to this branch. Do not carry it through
        // every current-history read/recovery poll frame, even when the writer is already open.
        // Erase the already-boxed initializer's type so callers' Send proofs do not recursively
        // traverse the entire schema migration future through every close/archive owner.
        let writer = self
            .state
            .writer
            .get_or_try_init(
                || -> futures::future::BoxFuture<'static, Result<HistoryConnection>> {
                    Box::pin(self.clone().initialize_writer(mode))
                },
            )
            .await?;
        Ok(Some(writer))
    }

    async fn initialize_writer(
        self,
        mode: crate::studio::paths::SqliteFileMode,
    ) -> Result<HistoryConnection> {
        schema::inspect_existing(&self.state.path, &self.state.thread_id).await?;
        let parent = self
            .state
            .path
            .parent()
            .context("history database path has no parent directory")?;
        if matches!(mode, crate::studio::paths::SqliteFileMode::Create) {
            tokio::fs::create_dir_all(parent).await?;
        }
        let db = connect(&self.state.path, mode).await?;
        let (database_id, schema_version) =
            match schema::initialize(&db, &self.state.thread_id).await {
                Ok(identity) => identity,
                Err(error) => {
                    if let Err(cleanup) = db.close().await {
                        return Err(crate::studio::startup::cleanup_error(cleanup).context(error));
                    }
                    return Err(error);
                }
            };
        Ok(HistoryConnection {
            db,
            database_id,
            schema_version,
        })
    }

    /// Upgrades existing history before an active owner seeds its canonical projection.
    pub(crate) async fn prepare_activation(&self) -> Result<()> {
        // Envelope migrations evolve independently from the table format. Every existing
        // activation lets the official migrator decide which named steps remain pending.
        self.open_writer(crate::studio::paths::SqliteFileMode::ReadWrite)
            .await?;
        Ok(())
    }

    pub(crate) async fn watermark(&self) -> Result<u64> {
        match self.reader().await? {
            Some(connection) => connection_watermark(connection).await,
            None => Ok(0),
        }
    }
}

async fn connect(
    path: &Path,
    mode: crate::studio::paths::SqliteFileMode,
) -> Result<DatabaseConnection> {
    let mut options = crate::studio::paths::sqlite_file_options(path, mode, |options| {
        options
            .journal_mode(SqliteJournalMode::Wal)
            .synchronous(SqliteSynchronous::Full)
            .busy_timeout(Duration::from_secs(5))
            .foreign_keys(true)
    })
    .await?;
    options
        .max_connections(1)
        .min_connections(1)
        .connect_timeout(Duration::from_secs(8))
        .acquire_timeout(Duration::from_secs(8))
        .sqlx_logging(false);
    Ok(Database::connect(options).await?)
}

/// 一次历史写事务在放弃之前额外重试的次数（每次都会先等 `busy_timeout`）。
const HISTORY_WRITE_RETRIES: u32 = 2;

/// Begins one history write transaction that takes the write lock up front.
///
/// `BEGIN DEFERRED` only upgrades its read lock when the first write statement runs, and SQLite
/// reports `SQLITE_BUSY` for a failed upgrade *without* invoking the busy handler — so the
/// configured `busy_timeout` cannot serialize two writers that both read before they write. Every
/// history write reads the applied waterline and then writes it in
/// the same transaction, so it must start as a writer: `BEGIN IMMEDIATE` makes the busy handler do
/// the waiting, and a transaction that still finds the lock held past the timeout is retried a
/// bounded number of times before it is reported. A structural failure (constraint, corruption)
/// is never retried.
async fn begin_write(db: &DatabaseConnection) -> Result<sea_orm::DatabaseTransaction> {
    let mut attempt: u32 = 0;
    loop {
        let started = db
            .begin_with_options(TransactionOptions {
                sqlite_transaction_mode: Some(SqliteTransactionMode::Immediate),
                ..Default::default()
            })
            .await;
        match started {
            Ok(tx) => return Ok(tx),
            Err(error)
                if attempt < HISTORY_WRITE_RETRIES && is_retryable_write(&error.to_string()) =>
            {
                attempt += 1;
                // The busy handler already waited for the lock; a short pause only gives the other
                // writer a chance to commit before this attempt re-acquires it.
                tokio::time::sleep(Duration::from_millis(50 * u64::from(attempt))).await;
            }
            Err(error) => return Err(error.into()),
        }
    }
}

/// Opens an *existing* history database read-only, without creating or upgrading anything.
///
/// `mode=ro` makes SQLite refuse to create a missing file, and no schema/journal PRAGMA that would
/// mutate the database is issued here; a concurrent WAL writer stays visible through its
/// checkpoint, so cold pagination is neither gated on nor able to disturb the writer.
async fn connect_read_only(path: &Path) -> Result<DatabaseConnection> {
    let mut options = crate::studio::paths::sqlite_file_options(
        path,
        crate::studio::paths::SqliteFileMode::ReadOnly,
        |options| {
            // Only read-safe settings: cold reads must not change the journal or schema.
            options
                .busy_timeout(Duration::from_secs(5))
                .foreign_keys(true)
        },
    )
    .await?;
    options
        .max_connections(1)
        .min_connections(1)
        .connect_timeout(Duration::from_secs(8))
        .acquire_timeout(Duration::from_secs(8))
        .sqlx_logging(false);
    Database::connect(options).await.with_context(|| {
        format!(
            "history database could not be opened read-only: {}",
            path.display()
        )
    })
}

/// Validates an existing history database's schema, Thread and database identity without writing.
///
/// A missing identity row, an unsupported schema version, a foreign Thread or an empty database id
/// fails closed so a cold read reports the damage instead of adopting or rebuilding the store.
async fn validate_existing(db: &impl ConnectionTrait, thread_id: &str) -> Result<(String, i64)> {
    let (database_id, version) = validate_existing_identity(db, thread_id).await?;
    ensure!(
        version == HISTORY_SCHEMA_VERSION,
        "history schema {version} requires explicit storage preparation or is unsupported; existing data preserved"
    );
    schema::validate_current(db, thread_id).await?;
    Ok((database_id, version))
}

/// Minimal existing-file identity gate, also used before explicit legacy content preparation.
/// The current reader adds its own strict format and table checks in validate_existing.
async fn validate_existing_identity(
    db: &impl ConnectionTrait,
    thread_id: &str,
) -> Result<(String, i64)> {
    let row = db
        .query_one_raw(statement(
            "SELECT schema_version,database_id,thread_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await
        .context("history database has no readable identity table")?;
    let row = row.context("history database identity row is missing")?;
    let version: i64 = row.try_get("", "schema_version")?;
    ensure!(
        (1..=HISTORY_SCHEMA_VERSION).contains(&version),
        "unsupported history schema {version}; existing data preserved"
    );
    let owner: String = row.try_get("", "thread_id")?;
    ensure!(
        owner == thread_id,
        "history database belongs to another Thread"
    );
    let database_id: String = row.try_get("", "database_id")?;
    ensure!(
        !database_id.is_empty(),
        "history database identity is empty"
    );
    Ok((database_id, version))
}

/// Current durable write sequence of one already-open connection.
async fn connection_watermark(connection: &HistoryConnection) -> Result<u64> {
    u64::try_from(applied_write_seq(&connection.db).await?)
        .context("negative history write sequence")
}

/// Creates or validates the schema and returns the owning database identity.
fn statement(sql: &str, values: Vec<Value>) -> Statement {
    Statement::from_sql_and_values(DatabaseBackend::Sqlite, sql, values)
}

/// Writes one terminal fact receipt in the same transaction as the effect that produced it.
/// The digest is taken from the canonical source payload (the committed record), so a repeated
/// write of the same `(item_id, revision)` is idempotent while a different payload for an
/// already-recorded revision is an identity conflict that fails the whole effect transaction.
/// Receipts are immutable per revision: a newer revision is a new row, never an overwrite of an
/// older terminal fact.
async fn write_fact_receipt(
    db: &impl ConnectionTrait,
    write_seq: i64,
    receipt: &FactReceiptWrite,
) -> Result<()> {
    ensure!(
        !receipt.item_id.is_empty(),
        "durable fact receipt identity must not be empty"
    );
    let digest = pl_core::context::content_hash(receipt.payload.as_bytes());
    let revision = integer(receipt.revision)?;
    let existing = db
        .query_one_raw(statement(
            "SELECT digest,kind FROM history_fact_receipts WHERE item_id=? AND revision=?",
            vec![receipt.item_id.clone().into(), revision.into()],
        ))
        .await?;
    if let Some(row) = existing {
        let stored: String = row.try_get("", "digest")?;
        ensure!(
            stored == digest && row.try_get::<String>("", "kind")? == receipt.kind,
            "durable fact receipt {}@{} conflicts with its recorded payload",
            receipt.item_id,
            receipt.revision
        );
        if receipt.kind == "reviewDeliveryException" {
            // This is an immutable producer fact, not a refreshed decision projection. Preserve
            // the effect that first committed it even when the same carrier is replayed later.
            return Ok(());
        }
        db.execute_raw(statement(
            "UPDATE history_fact_receipts SET kind=?,payload=?,last_write_seq=?
             WHERE item_id=? AND revision=?",
            vec![
                receipt.kind.to_owned().into(),
                receipt.payload.clone().into(),
                write_seq.into(),
                receipt.item_id.clone().into(),
                revision.into(),
            ],
        ))
        .await?;
        return Ok(());
    }
    db.execute_raw(statement(
        "INSERT INTO history_fact_receipts(item_id,revision,kind,digest,payload,last_write_seq)
         VALUES(?,?,?,?,?,?)",
        vec![
            receipt.item_id.clone().into(),
            revision.into(),
            receipt.kind.to_owned().into(),
            digest.into(),
            receipt.payload.clone().into(),
            write_seq.into(),
        ],
    ))
    .await?;
    Ok(())
}

async fn applied_write_seq(db: &impl ConnectionTrait) -> Result<i64> {
    Ok(db
        .query_one_raw(statement(
            "SELECT applied_write_seq FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("history metadata is missing")?
        .try_get("", "applied_write_seq")?)
}

fn integer(value: impl TryInto<i64>) -> Result<i64> {
    value
        .try_into()
        .map_err(|_| anyhow::anyhow!("history integer exceeds SQLite range"))
}

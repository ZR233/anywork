use std::path::{Path, PathBuf};
use std::time::Duration;

use anyhow::{Context, Result, bail, ensure};
use sea_orm::sqlx::sqlite::{SqliteJournalMode, SqliteSynchronous};
use sea_orm::{
    ConnectOptions, ConnectionTrait, Database, DatabaseBackend, DatabaseConnection, Statement,
};

use super::schema::{STUDIO_DATABASE_SCHEMA_VERSION, migrate};
use crate::studio::catalog::CatalogStore;
use crate::studio::paths::{SqliteFileMode, StudioPaths, default_db_path, sqlite_file_options};
use crate::studio::records::WorkspaceRecord;
use crate::studio::store::settings::SettingsStore;
use crate::studio::store::workspaces::WorkspaceStore;
use crate::studio::store::{StudioDatabaseError, StudioStore};

/// 可原地升级到当前 schema 的上一版本；模式匹配需要 const 模式。
const UPGRADEABLE_STUDIO_DATABASE_SCHEMA_VERSION: i64 = 22;

/// Whether a resolved Studio home already owns persistent state from an earlier run.
///
/// The product database is deliberately *not* part of this decision: every installation, including
/// a brand-new one, materializes `<home>/studio/studio.sqlite`, so its presence says nothing about
/// prior v2 state. The evidence is a session or migration directory, call facts,
/// attachment-draft state, or an existing canonical document. Call and draft state are usable as
/// evidence because a fresh open publishes the three canonical documents before it opens the
/// call store and before the runtime creates its draft root, so either without the documents
/// means the fact source was lost
/// rather than never written.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum InstallationState {
    /// No prior Studio state: missing documents describe a new, empty installation.
    Fresh,
    /// Prior Studio state exists: every canonical document must already be on disk.
    Existing,
}

impl StudioStore {
    pub async fn default_app() -> Result<Self> {
        Self::open_database(&default_db_path()?).await
    }

    pub async fn open(path: impl AsRef<Path>) -> Result<Self> {
        Self::open_database(path.as_ref()).await
    }

    pub async fn open_memory() -> Result<Self> {
        let db = connect_memory().await?;
        migrate(&db).await?;
        validate_database(&db).await?;
        let home = tempfile::Builder::new()
            .prefix("anywork-memory-store-")
            .tempdir()?
            .keep();
        let paths = StudioPaths::resolve(Some(home))?;
        let calls =
            crate::studio::storage::calls::CallsStore::open(&paths.calls_database()).await?;
        // A brand-new in-memory store for tests starts from empty canonical documents and never
        // reads the retired product tables.
        let (catalog, settings, workspaces) =
            load_canonical_documents(&paths, InstallationState::Fresh).await?;
        let store = Self {
            db,
            calls,
            catalog,
            settings,
            workspaces,
            thread_persistence: Default::default(),
            attachment_lock: Default::default(),
            paths,
        };
        Ok(store)
    }

    pub(super) async fn open_database(path: &Path) -> Result<Self> {
        let store = Self::prepare_database(path).await?;
        store.calls.start().await;
        Ok(store)
    }

    pub(crate) async fn prepare_database(path: &Path) -> Result<Self> {
        let path = resolve_configured_database_path(path).await?;
        let paths = StudioPaths::resolve(Some(studio_home_from_database(&path)?))?;
        // Inspect installation facts before any SQLite owner can create or migrate a file.
        let installation = detect_installation(&paths).await?;
        if installation == InstallationState::Existing {
            for (path, name) in [
                (paths.catalog_file(), "catalog.toml"),
                (paths.settings_file(), "settings.toml"),
                (paths.workspaces_file(), "workspaces.toml"),
                (paths.database(), "studio.sqlite"),
                (paths.calls_database(), "calls/calls.sqlite"),
            ] {
                require_canonical_document(&path, name).await?;
            }
        }
        let database_exists = tokio::fs::try_exists(&path).await?;
        let family_exists = database_family_exists(&path).await?;
        if database_exists {
            inspect_database(&path).await?;
        } else if family_exists {
            return Err(StudioDatabaseError::CorruptDatabase {
                reason: "orphan Studio WAL/SHM files".into(),
            }
            .into());
        }
        let db = connect_sqlite(
            sqlite_file_options(&path, SqliteFileMode::Create, |options| {
                configure_sqlite(options, SqliteSynchronous::Full)
            })
            .await?,
            /* max_connections */ 1,
        )
        .await?;
        let initialization = async {
            migrate(&db).await?;
            validate_database(&db).await
        }
        .await;
        if let Err(error) = initialization {
            return Err(match db.close().await {
                Ok(()) => error.context("Studio database initialization failed"),
                Err(cleanup) => crate::studio::startup::cleanup_error(cleanup).context(error),
            });
        }
        // Canonical TOML is the only fact source for directory and settings reads. A missing or
        // corrupt document on an installation that already owns state fails startup instead of
        // being replaced by an empty default; no retired SQLite table is read here.
        let documents = match load_canonical_documents(&paths, installation).await {
            Ok(documents) => documents,
            Err(error) => {
                let close = db.close().await;
                return Err(match close {
                    Ok(()) => error,
                    Err(close_error) => {
                        crate::studio::startup::cleanup_error(close_error).context(error)
                    }
                });
            }
        };
        let (catalog, settings, workspaces) = documents;
        let calls =
            match crate::studio::storage::calls::CallsStore::prepare(&paths.calls_database()).await
            {
                Ok(calls) => calls,
                Err(error) => {
                    db.close().await.context(
                        "failed to close product database after calls preparation failed",
                    )?;
                    return Err(error);
                }
            };
        let store = Self {
            db,
            calls,
            catalog,
            settings,
            workspaces,
            thread_persistence: Default::default(),
            attachment_lock: Default::default(),
            paths,
        };
        Ok(store)
    }

    pub(crate) async fn close(&self) -> Result<()> {
        let (calls, product) = tokio::join!(self.calls.close(), self.db.close_by_ref());
        calls?;
        product?;
        Ok(())
    }

    pub async fn list_projects(&self) -> Result<Vec<WorkspaceRecord>> {
        let mut entries = self
            .workspaces()
            .entries()
            .into_iter()
            .filter(|entry| !entry.closed)
            .collect::<Vec<_>>();
        entries.sort_by(|left, right| {
            right
                .last_opened_at
                .cmp(&left.last_opened_at)
                .then_with(|| right.updated_at.cmp(&left.updated_at))
                .then_with(|| right.id.cmp(&left.id))
        });
        Ok(entries.into_iter().map(|entry| entry.project()).collect())
    }

    /// 聚合冷加载：按 path 找到既有 Project 行身份事实。
    pub(in crate::studio) async fn find_project_by_path(
        &self,
        path: &str,
        ssh_alias: Option<&str>,
    ) -> Result<Option<ProjectRow>> {
        Ok(self
            .workspaces()
            .find_by_path(path, ssh_alias)
            .map(|entry| ProjectRow {
                id: entry.id,
                kind: entry.kind,
                name: entry.name,
                created_at: entry.created_at,
            }))
    }

    pub async fn read_project(&self, workspace_id: &str) -> Result<Option<WorkspaceRecord>> {
        Ok(self
            .workspaces()
            .get(workspace_id)
            .map(|entry| entry.project()))
    }
}

/// Derives the Studio home that owns a product database file.
///
/// The canonical layout places the product database at `<home>/data/studio.sqlite`. Explicit
/// isolated database files used by embedding/tests retain their parent as home; retired product
/// locations are rejected before SQLite is opened, never treated as runtime fallback roots.
fn studio_home_from_database(database: &Path) -> Result<PathBuf> {
    let parent = database
        .parent()
        .context("Studio database path has no parent directory")?;
    if parent.file_name().is_some_and(|name| name == "data") {
        return parent
            .parent()
            .map(Path::to_path_buf)
            .context("data root has no home");
    }
    ensure!(
        !parent
            .file_name()
            .is_some_and(|name| name == "v2" || name == "studio"),
        super::SessionLayoutMigrationFailed {
            source: anyhow::anyhow!(
                "retired Studio database locations are not runtime fallback roots; use explicit v2 layout migration"
            )
        }
    );
    Ok(parent.to_path_buf())
}

/// `find_project_by_path` 返回的持久身份事实。
#[derive(Debug, Clone)]
pub(in crate::studio) struct ProjectRow {
    pub(in crate::studio) id: String,
    pub(in crate::studio) kind: pl_protocol::studio::WorkspaceKind,
    pub(in crate::studio) name: String,
    pub(in crate::studio) created_at: i64,
}

/// Classifies the resolved Studio home before any store-owned file is created.
async fn detect_installation(paths: &StudioPaths) -> Result<InstallationState> {
    let mut entries = tokio::fs::read_dir(paths.data_dir()).await?;
    while let Some(entry) = entries.next_entry().await? {
        if !entry.file_type().await?.is_dir()
            || !matches!(entry.file_name().to_str(), Some("model-catalogs" | "temp"))
        {
            return Ok(InstallationState::Existing);
        }
    }
    Ok(InstallationState::Fresh)
}

/// Loads the three canonical directory/settings documents.
///
/// A fresh installation may start from missing documents: an absent file is the empty document it
/// will create on its first write. An installation that already owns state must have every
/// canonical document on disk, because a missing one means the fact source was lost; startup fails
/// closed instead of silently substituting an empty document and masking migrated user data.
async fn load_canonical_documents(
    paths: &StudioPaths,
    installation: InstallationState,
) -> Result<(CatalogStore, SettingsStore, WorkspaceStore)> {
    if installation == InstallationState::Existing {
        require_canonical_document(&paths.catalog_file(), "catalog.toml").await?;
        require_canonical_document(&paths.settings_file(), "settings.toml").await?;
        require_canonical_document(&paths.workspaces_file(), "workspaces.toml").await?;
    }
    let catalog = CatalogStore::load(paths.catalog_file()).await?;
    let settings = SettingsStore::load(paths.settings_file()).await?;
    let workspaces = WorkspaceStore::load(paths.workspaces_file()).await?;
    validate_directory_references(&catalog, &workspaces)
        .map_err(crate::studio::startup::data_error)?;
    if installation == InstallationState::Fresh {
        // A truly new installation starts with complete, empty canonical documents: the fact source
        // exists before the first mutation, and a later missing document is unambiguously a loss
        // instead of an as-yet unwritten file. Nothing is created when the home already owns state,
        // because that path fails closed above.
        catalog.persist_if_absent().await?;
        settings.persist_if_absent().await?;
        workspaces.persist_if_absent().await?;
    }
    Ok((catalog, settings, workspaces))
}

pub(super) fn validate_directory_references(
    catalog: &CatalogStore,
    workspaces: &WorkspaceStore,
) -> Result<()> {
    use std::collections::{BTreeMap, BTreeSet};
    let entries = catalog.entries();
    let threads = entries
        .iter()
        .map(|entry| (entry.id.as_str(), entry))
        .collect::<BTreeMap<_, _>>();
    let projects = workspaces
        .entries()
        .into_iter()
        .map(|entry| entry.id)
        .collect::<BTreeSet<_>>();
    for entry in &entries {
        ensure!(
            projects.contains(&entry.workspace_id),
            "catalog references a missing project"
        );
        if let Some(parent_id) = &entry.parent_thread_id {
            let parent = threads
                .get(parent_id.as_str())
                .context("catalog references a missing parent")?;
            let root = threads
                .get(entry.root_thread_id.as_str())
                .context("catalog references a missing root")?;
            ensure!(
                parent.workspace_id == entry.workspace_id
                    && root.workspace_id == entry.workspace_id
                    && root.parent_thread_id.is_none()
                    && parent.root_thread_id == entry.root_thread_id,
                "catalog parent/root references are inconsistent"
            );
        }
    }
    let mut checked = BTreeSet::new();
    for entry in &entries {
        let mut path = BTreeSet::new();
        let mut current = entry;
        while !checked.contains(current.id.as_str()) {
            ensure!(
                path.insert(current.id.as_str()),
                "catalog parent references contain a cycle"
            );
            let Some(parent) = &current.parent_thread_id else {
                break;
            };
            current = threads
                .get(parent.as_str())
                .context("catalog parent is missing")?;
        }
        checked.extend(path);
    }
    Ok(())
}

async fn require_canonical_document(path: &Path, name: &str) -> Result<()> {
    if !tokio::fs::try_exists(path).await? {
        return Err(crate::studio::startup::data_error(anyhow::anyhow!(
            "Studio {name} is missing on an existing installation ({})",
            path.display()
        )));
    }
    Ok(())
}

async fn connect_memory() -> Result<DatabaseConnection> {
    let mut options = ConnectOptions::new("sqlite::memory:");
    options.map_sqlx_sqlite_opts(|options| configure_sqlite(options, SqliteSynchronous::Normal));
    connect_sqlite(options, /* max_connections */ 1).await
}

async fn connect_sqlite(
    mut options: ConnectOptions,
    max_connections: u32,
) -> Result<DatabaseConnection> {
    options
        .max_connections(max_connections)
        .min_connections(1)
        .connect_timeout(Duration::from_secs(8))
        .acquire_timeout(Duration::from_secs(8))
        .sqlx_logging(false);
    Ok(Database::connect(options).await?)
}

fn configure_sqlite(
    options: sea_orm::sqlx::sqlite::SqliteConnectOptions,
    synchronous: SqliteSynchronous,
) -> sea_orm::sqlx::sqlite::SqliteConnectOptions {
    options
        .journal_mode(SqliteJournalMode::Wal)
        .synchronous(synchronous)
        .busy_timeout(Duration::from_secs(5))
        .foreign_keys(true)
}

async fn connect_read_only_database(path: &Path) -> Result<DatabaseConnection> {
    let mut options =
        sqlite_file_options(path, SqliteFileMode::ReadOnly, |options| options).await?;
    options
        .max_connections(1)
        .min_connections(1)
        .connect_timeout(Duration::from_secs(8))
        .acquire_timeout(Duration::from_secs(8))
        .sqlx_logging(false);
    Database::connect(options)
        .await
        .with_context(|| format!("无法以只读方式打开 Studio 数据库：{}", path.display()))
}

async fn inspect_database(path: &Path) -> Result<()> {
    let database = connect_read_only_database(path).await?;
    let version = async {
        super::schema::preflight(&database).await?;
        database_schema_version(&database).await
    }
    .await;
    let validation = match version {
        Ok(STUDIO_DATABASE_SCHEMA_VERSION) => validate_database(&database).await,
        // 上一个大版本的 v2 库可以在打开后原地升级；更早的 dev 版本仍交给启动入口。
        Ok(0) => Ok(()),
        Ok(version)
            if (UPGRADEABLE_STUDIO_DATABASE_SCHEMA_VERSION..STUDIO_DATABASE_SCHEMA_VERSION)
                .contains(&version) =>
        {
            Ok(())
        }
        Ok(19..=21) => Err(StudioDatabaseError::StorageMigrationRequired.into()),
        Ok(found) => Err(StudioDatabaseError::UnsupportedSchema {
            found,
            supported: STUDIO_DATABASE_SCHEMA_VERSION,
        }
        .into()),
        Err(error) => Err(error),
    };
    let close = database.close().await;
    match (validation, close) {
        (Ok(state), Ok(())) => Ok(state),
        (Err(error), Ok(())) => Err(error),
        (Ok(_), Err(error)) => Err(error).context("failed to close Studio schema probe"),
        (Err(error), Err(close_error)) => {
            Err(crate::studio::startup::cleanup_error(close_error).context(error))
        }
    }
}

async fn validate_database(db: &DatabaseConnection) -> Result<()> {
    validate_database_version(db, STUDIO_DATABASE_SCHEMA_VERSION).await
}

async fn validate_database_version(db: &DatabaseConnection, expected_version: i64) -> Result<()> {
    let version = database_schema_version(db).await?;
    if version != expected_version {
        return Err(StudioDatabaseError::UnsupportedSchema {
            found: version,
            supported: expected_version,
        }
        .into());
    }

    let rows = db
        .query_all_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "PRAGMA quick_check".to_string(),
        ))
        .await?;
    let results = rows
        .into_iter()
        .map(|row| row.try_get::<String>("", "quick_check"))
        .collect::<std::result::Result<Vec<_>, _>>()?;
    if results.as_slice() != ["ok"] {
        return Err(StudioDatabaseError::CorruptDatabase {
            reason: results.join("; "),
        }
        .into());
    }

    let actual = schema_fingerprint(db).await?;
    let expected = expected_schema_fingerprint().await?;
    if actual != expected {
        return Err(StudioDatabaseError::CorruptDatabase {
            reason: "incompatible schema fingerprint".into(),
        }
        .into());
    }
    Ok(())
}

async fn database_schema_version(db: &impl sea_orm::ConnectionTrait) -> Result<i64> {
    let row = db
        .query_one_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            "PRAGMA user_version".to_string(),
        ))
        .await?
        .ok_or_else(|| anyhow::anyhow!("SQLite 未返回 user_version"))?;
    Ok(row.try_get("", "user_version")?)
}

async fn expected_schema_fingerprint() -> Result<String> {
    let database = connect_memory().await?;
    migrate(&database).await?;
    let fingerprint = schema_fingerprint(&database).await;
    database.close().await?;
    fingerprint
}

async fn schema_fingerprint(db: &DatabaseConnection) -> Result<String> {
    schema_fingerprint_where(db, "1 = 1").await
}

async fn schema_fingerprint_where(db: &DatabaseConnection, predicate: &str) -> Result<String> {
    let rows = db
        .query_all_raw(Statement::from_string(
            DatabaseBackend::Sqlite,
            format!(
                "SELECT type, name, tbl_name, sql
             FROM sqlite_schema
             WHERE name NOT LIKE 'sqlite_%'
               AND tbl_name <> 'seaql_migrations'
               AND type IN ('table', 'index')
               AND sql IS NOT NULL
               AND {predicate}
             ORDER BY type, name"
            ),
        ))
        .await?;
    let mut entries = Vec::with_capacity(rows.len());
    for row in rows {
        let kind: String = row.try_get("", "type")?;
        let name: String = row.try_get("", "name")?;
        let table: String = row.try_get("", "tbl_name")?;
        let sql: String = row.try_get("", "sql")?;
        let normalized_sql = sql.split_whitespace().collect::<Vec<_>>().join(" ");
        entries.push(format!("{kind}:{name}:{table}:{normalized_sql}"));
    }
    Ok(format!("v1:{}", entries.join("|")))
}

async fn resolve_configured_database_path(path: &Path) -> Result<PathBuf> {
    let path = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()?.join(path)
    };
    let file_name = path
        .file_name()
        .context("configured Studio database path has no file name")?
        .to_os_string();
    let parent = path
        .parent()
        .context("configured Studio database path has no parent")?;
    tokio::fs::create_dir_all(parent).await?;
    let parent = std::fs::canonicalize(parent)
        .context("failed to resolve configured Studio database directory")?;
    let resolved = parent.join(file_name);
    if tokio::fs::try_exists(&resolved).await? {
        validate_database_family_member(&resolved, &parent)?;
    }
    Ok(resolved)
}

async fn database_family_exists(path: &Path) -> Result<bool> {
    for member in database_family_paths(path) {
        if tokio::fs::try_exists(member).await? {
            return Ok(true);
        }
    }
    Ok(false)
}

fn validate_database_family_member(path: &Path, expected_parent: &Path) -> Result<()> {
    ensure!(
        path.parent() == Some(expected_parent),
        "Studio database cleanup target escaped its configured directory"
    );
    let metadata = std::fs::symlink_metadata(path)
        .with_context(|| format!("failed to inspect Studio database file {}", path.display()))?;
    if pl_tool::workspace::path_safety::is_link_or_reparse(&metadata) || !metadata.is_file() {
        bail!(
            "Studio database cleanup target is not a regular non-reparse file: {}",
            path.display()
        );
    }
    Ok(())
}

fn database_family_paths(path: &Path) -> [PathBuf; 3] {
    [
        path.to_path_buf(),
        sidecar_path(path, "-wal"),
        sidecar_path(path, "-shm"),
    ]
}

fn sidecar_path(path: &Path, suffix: &str) -> PathBuf {
    let mut value = path.as_os_str().to_os_string();
    value.push(suffix);
    PathBuf::from(value)
}

#[cfg(test)]
mod major_version_storage_tests {
    use super::*;

    #[tokio::test]
    async fn existing_installation_requires_both_databases_before_any_creation() -> Result<()> {
        for missing_calls in [false, true] {
            let temp = tempfile::tempdir()?;
            let paths = StudioPaths::from_home(temp.path().to_owned());
            let store = StudioStore::prepare_database(&paths.database()).await?;
            store.close().await?;
            let path = if missing_calls {
                paths.calls_database()
            } else {
                paths.database()
            };
            for member in database_family_paths(&path) {
                if member.exists() {
                    tokio::fs::remove_file(member).await?;
                }
            }
            let catalog = tokio::fs::read(paths.catalog_file()).await?;
            for _ in 0..2 {
                let error = StudioStore::prepare_database(&paths.database())
                    .await
                    .err()
                    .context("missing database must not be recreated")?;
                assert!(format!("{error:#}").contains("is missing on an existing installation"));
                assert!(
                    database_family_paths(&path)
                        .iter()
                        .all(|path| !path.exists())
                );
                assert_eq!(tokio::fs::read(paths.catalog_file()).await?, catalog);
            }
        }
        Ok(())
    }

    #[tokio::test]
    async fn retired_database_locations_are_rejected_before_open_or_rebuild() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        for name in [
            "studio/studio.sqlite",
            "v2/studio.sqlite",
            "studio/v2/studio.sqlite",
        ] {
            let source = temp.path().join(name);
            tokio::fs::create_dir_all(source.parent().context("source parent")?).await?;
            tokio::fs::write(&source, b"original retired bytes, not a SQLite fixture").await?;
            let error = match StudioStore::open(&source).await {
                Ok(_) => anyhow::bail!("retired product root was accepted"),
                Err(error) => error,
            };
            assert!(format!("{error:#}").contains("retired Studio database locations"));
            assert_eq!(
                tokio::fs::read(&source).await?,
                b"original retired bytes, not a SQLite fixture"
            );
            assert!(!paths.data_dir().exists());
        }
        Ok(())
    }

    #[tokio::test]
    async fn old_sessions_are_never_imported_or_recreated() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let old_session = temp.path().join("sessions/old-thread/state.toml");
        let old_catalog = temp.path().join("catalog.toml");
        let old_product = temp.path().join("studio/studio.sqlite");
        let config = temp.path().join("config.toml");
        for (path, data) in [
            (&old_session, b"old checkpoint".as_slice()),
            (&old_catalog, b"old catalog".as_slice()),
            (&old_product, b"old product database".as_slice()),
            (&config, b"provider configuration".as_slice()),
        ] {
            tokio::fs::create_dir_all(path.parent().expect("test path parent")).await?;
            tokio::fs::write(path, data).await?;
        }
        let store = StudioStore::open(paths.database()).await?;
        assert!(store.catalog().entries().is_empty());
        assert!(tokio::fs::try_exists(paths.catalog_file()).await?);
        for (path, expected) in [
            (&old_session, b"old checkpoint".as_slice()),
            (&old_catalog, b"old catalog".as_slice()),
            (&old_product, b"old product database".as_slice()),
            (&config, b"provider configuration".as_slice()),
        ] {
            assert_eq!(tokio::fs::read(path).await?, expected);
        }

        tokio::fs::remove_file(paths.catalog_file()).await?;
        let error = match StudioStore::open(paths.database()).await {
            Ok(_) => anyhow::bail!("a missing v2 catalog was accepted"),
            Err(error) => error,
        };
        assert!(error.to_string().contains("catalog.toml is missing"));
        assert_eq!(tokio::fs::read(old_catalog).await?, b"old catalog");
        Ok(())
    }
}

#[cfg(test)]
mod schema_upgrade_tests {
    use super::*;

    #[tokio::test]
    async fn v2_product_versions_drop_only_retired_mirrors_and_keep_independent_facts() -> Result<()>
    {
        for version in 22..=26 {
            let db = connect_memory().await?;
            db.execute_unprepared(include_str!("product_schema.sql"))
                .await?;
            db.execute_unprepared(include_str!("agent_evaluations.sql"))
                .await?;
            if version < 25 {
                db.execute_unprepared("ALTER TABLE threads DROP COLUMN explicitly_closed")
                    .await?;
            }
            if version < 24 {
                db.execute_unprepared("ALTER TABLE threads DROP COLUMN delegation_mode; ALTER TABLE threads DROP COLUMN delegation_preference; ALTER TABLE threads DROP COLUMN frozen_model_json").await?;
            }
            if version < 23 {
                db.execute_unprepared("ALTER TABLE threads DROP COLUMN last_user_message_at")
                    .await?;
            }
            db.execute_unprepared(&format!("PRAGMA user_version={version}"))
                .await?;
            db.execute_unprepared("INSERT INTO studio_objects VALUES ('thread','kept-owner','unknownIndependentFact',7,99,'opaque bytes','original hash',123); INSERT INTO agent_evaluations (agent_id,parent_agent_id,account_id,model_id,profile_id,mode,preference,turn_id,revision,task_category,outcome,comment,created_at,updated_at) VALUES ('kept-agent','parent','account','model','profile','profile','balanced','turn',4,'unknown','notRated','kept comment',1,2)").await?;
            if version < 24 {
                // Evaluations were introduced in schema 24, not present in frozen 22/23.
                db.execute_unprepared("DROP TABLE agent_evaluations")
                    .await?;
            }
            migrate(&db).await?;
            validate_database(&db).await?;
            let row = db.query_one_raw(Statement::from_string(DatabaseBackend::Sqlite,"SELECT revision,schema_version,payload_json,payload_hash,updated_at FROM studio_objects WHERE owner_id='kept-owner'")).await?.context("retained product fact")?;
            assert_eq!(row.try_get_by_index::<i64>(0)?, 7);
            assert_eq!(row.try_get_by_index::<i64>(1)?, 99);
            assert_eq!(row.try_get_by_index::<String>(2)?, "opaque bytes");
            assert_eq!(row.try_get_by_index::<String>(3)?, "original hash");
            assert_eq!(row.try_get_by_index::<i64>(4)?, 123);
            let row = db
                .query_one_raw(Statement::from_string(
                    DatabaseBackend::Sqlite,
                    "SELECT comment,revision FROM agent_evaluations WHERE agent_id='kept-agent'",
                ))
                .await?;
            if version >= 24 {
                let row = row.context("retained evaluation")?;
                assert_eq!(row.try_get_by_index::<String>(0)?, "kept comment");
                assert_eq!(row.try_get_by_index::<i64>(1)?, 4);
            } else {
                assert!(row.is_none());
            }
            for name in ["projects", "threads", "app_settings"] {
                assert!(
                    db.query_one_raw(Statement::from_sql_and_values(
                        DatabaseBackend::Sqlite,
                        "SELECT 1 FROM sqlite_schema WHERE name=?",
                        [name.into()]
                    ))
                    .await?
                    .is_none()
                );
            }
            migrate(&db).await?;
            db.close().await?;
        }
        Ok(())
    }
}

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
use crate::studio::records::ProjectRecord;
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
        // The data root is resolved once; every session, call and attachment path comes from the
        // canonical layout instead of being re-joined by each consumer.
        let paths = StudioPaths::resolve(Some(studio_home_from_database(&path)?))?;
        // Old-version publication state lives outside this version's data root and is never read.
        // Decide the canonical-document contract before opening anything that creates state of its
        // own: this classification must see the home as it was left by the previous run, and every
        // store below (calls, database) materializes files on a fresh open.
        let installation = detect_installation(&paths).await?;
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
        if let Err(error) = super::session_layout::migrate_flat_sessions(
            &store.paths,
            &store.catalog,
            &store.workspaces,
        )
        .await
        {
            let close = store.close().await;
            return Err(match close {
                Ok(()) => error,
                Err(close_error) => {
                    crate::studio::startup::cleanup_error(close_error).context(error)
                }
            });
        }
        Ok(store)
    }

    pub(crate) async fn close(&self) -> Result<()> {
        let (calls, product) = tokio::join!(self.calls.close(), self.db.close_by_ref());
        calls?;
        product?;
        Ok(())
    }

    pub async fn list_projects(&self) -> Result<Vec<ProjectRecord>> {
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

    pub async fn read_project(&self, project_id: &str) -> Result<Option<ProjectRecord>> {
        Ok(self
            .workspaces()
            .get(project_id)
            .map(|entry| entry.project()))
    }
}

/// Derives the Studio home that owns a product database file.
///
/// The canonical layout places the product database at `<home>/studio/v2/studio.sqlite`; a database
/// configured directly in its own directory keeps that directory as the home. Both cases resolve
/// the same relative layout for sessions, calls and attachments.
fn studio_home_from_database(database: &Path) -> Result<PathBuf> {
    let parent = database
        .parent()
        .context("Studio database path has no parent directory")?;
    if parent.file_name().is_some_and(|name| name == "v2")
        && parent
            .parent()
            .and_then(Path::file_name)
            .is_some_and(|name| name == "studio")
    {
        return parent
            .parent()
            .and_then(Path::parent)
            .map(Path::to_path_buf)
            .context("Studio versioned data directory has no home");
    }
    if parent.file_name().is_some_and(|name| name == "studio") {
        return parent
            .parent()
            .map(Path::to_path_buf)
            .context("Studio data directory has no parent");
    }
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
    for candidate in [
        paths.projects_dir(),
        paths.legacy_sessions_dir(),
        paths.migrations_dir(),
        paths.calls_database(),
        paths.attachment_drafts_dir(),
        paths.catalog_file(),
        paths.settings_file(),
        paths.workspaces_file(),
    ] {
        if tokio::fs::try_exists(&candidate).await? {
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

fn validate_directory_references(
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
            projects.contains(&entry.project_id),
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
                parent.project_id == entry.project_id
                    && root.project_id == entry.project_id
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

/// v2 内产品库结构升级：基线 v22/v23 的真实列布局，原地保全后校验 canonical 指纹。
#[cfg(test)]
mod v2_schema_upgrade_tests {
    use super::super::directory::{DirectoryDelta, ProjectDirectoryRecord, apply_directory_delta};
    use super::*;
    use sea_orm::TransactionTrait;

    #[tokio::test]
    async fn schema_24_catalog_3_closed_child_does_not_invent_close_intent() -> Result<()> {
        use crate::studio::entity as entities;
        use sea_orm::EntityTrait;
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        let mut delta = DirectoryDelta::upsert_project(ProjectDirectoryRecord {
            id: "preserved-project".into(),
            kind: pl_protocol::studio::WorkspaceKind::Project,
            name: "Preserved".into(),
            path: "/preserved".into(),
            ssh_alias: None,
            created_at: 1,
            updated_at: 2,
            last_opened_at: None,
            closed: false,
        });
        let (_, root) = DirectoryDelta::register_root_thread(
            "preserved-root".into(),
            "preserved-project",
            "Root",
            pl_protocol::ThreadModeId::simple(),
            pl_protocol::ThreadWorkspaceMode::Local,
            "/preserved".into(),
        );
        let mut child = root.clone();
        child.id = "preserved-child".into();
        child.agent_path = child.id.clone();
        child.parent_thread_id = Some(root.id.clone());
        child.status = pl_protocol::ThreadStatus::Closed;
        child.frozen_model = Some(pl_protocol::studio::NewThreadModelRoute {
            account_id: "original-account".into(),
            model_id: "original-model".into(),
            effort: Some("high".into()),
        });
        delta.thread_upserts = vec![root, child.clone()];
        let tx = store.database().begin().await?;
        apply_directory_delta(&store, &tx, &delta).await?;
        tx.commit().await?;
        store
            .database()
            .execute_unprepared(
                "ALTER TABLE threads DROP COLUMN explicitly_closed; DROP TABLE IF EXISTS seaql_migrations; PRAGMA user_version=24",
            )
            .await?;
        store.close().await?;
        drop(store);
        let mut catalog: toml::Table =
            toml::from_str(&tokio::fs::read_to_string(paths.catalog_file()).await?)?;
        catalog["schemaVersion"] = 3.into();
        for entry in catalog["entries"].as_array_mut().context("entries")? {
            entry
                .as_table_mut()
                .context("entry")?
                .remove("explicitlyClosed");
        }
        tokio::fs::write(paths.catalog_file(), toml::to_string(&catalog)?).await?;
        let upgraded = StudioStore::open(paths.database()).await?;
        assert_eq!(
            database_schema_version(upgraded.database()).await?,
            STUDIO_DATABASE_SCHEMA_VERSION
        );
        let saved = upgraded
            .catalog()
            .get(&child.id)
            .context("retained child")?;
        assert!(
            !saved.explicitly_closed,
            "old Closed must not imply parent close intent"
        );
        assert_eq!(saved.to_thread().status, pl_protocol::ThreadStatus::Idle);
        assert_eq!(saved.frozen_model, child.frozen_model);
        assert_eq!(saved.parent_thread_id, child.parent_thread_id);
        let row = entities::thread::Entity::find_by_id(&child.id)
            .one(upgraded.database())
            .await?
            .context("mirror")?;
        assert_eq!(row.explicitly_closed, 0);
        // Simulate a checkpoint-derived projection, then a delayed pre-close directory snapshot.
        upgraded.catalog().project_explicit_close(&child.id).await?;
        upgraded
            .persist_directory_summaries(&DirectoryDelta {
                thread_upserts: vec![child.clone()],
                ..Default::default()
            })
            .await?;
        let tx = upgraded.database().begin().await?;
        apply_directory_delta(
            &upgraded,
            &tx,
            &DirectoryDelta {
                thread_upserts: vec![child.clone()],
                ..Default::default()
            },
        )
        .await?;
        tx.commit().await?;
        assert!(
            upgraded
                .catalog()
                .get(&child.id)
                .context("projected child")?
                .explicitly_closed
        );
        assert_eq!(
            entities::thread::Entity::find_by_id(&child.id)
                .one(upgraded.database())
                .await?
                .context("projected mirror")?
                .explicitly_closed,
            1
        );
        upgraded.close().await?;
        let reopened = StudioStore::open(paths.database()).await?;
        assert!(
            reopened
                .catalog()
                .get(&child.id)
                .context("reopened child")?
                .explicitly_closed
        );
        reopened.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn schema_23_catalog_2_upgrade_and_evaluation_write_failure_preserve_v2_facts()
    -> Result<()> {
        use pl_protocol::{
            AgentEvaluation, AgentEvaluationOutcome, AgentTaskCategory, EvaluateAgentRequest,
        };
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        let mut delta = DirectoryDelta::upsert_project(ProjectDirectoryRecord {
            id: "kept-project".into(),
            kind: pl_protocol::studio::WorkspaceKind::Project,
            name: "既有工程".into(),
            path: "/retained-project".into(),
            ssh_alias: None,
            created_at: 10,
            updated_at: 20,
            last_opened_at: Some(30),
            closed: false,
        });
        let (thread_delta, old) = DirectoryDelta::register_root_thread(
            "kept-thread".into(),
            "kept-project",
            "保留的历史",
            pl_protocol::ThreadModeId::simple(),
            pl_protocol::ThreadWorkspaceMode::Local,
            "/retained-project".into(),
        );
        delta.thread_upserts = thread_delta.thread_upserts;
        let tx = store.database().begin().await?;
        apply_directory_delta(&store, &tx, &delta).await?;
        tx.commit().await?;
        // Exact HEAD 767771084f6c schema 23: these columns/table did not exist. No
        // session/history/calls table is rebuilt, and the old directory is schema 2.
        store
            .database()
            .execute_unprepared(
                "ALTER TABLE threads DROP COLUMN delegation_mode;
            ALTER TABLE threads DROP COLUMN delegation_preference;
            ALTER TABLE threads DROP COLUMN frozen_model_json;
            ALTER TABLE threads DROP COLUMN explicitly_closed;
            DROP TABLE agent_evaluations;
            DROP TABLE IF EXISTS seaql_migrations; PRAGMA user_version=23;",
            )
            .await?;
        store.close().await?;
        drop(store);
        let mut catalog: toml::Table =
            toml::from_str(&tokio::fs::read_to_string(paths.catalog_file()).await?)?;
        catalog["schemaVersion"] = 2.into();
        for entry in catalog["entries"]
            .as_array_mut()
            .context("catalog entries")?
        {
            let entry = entry.as_table_mut().context("catalog entry")?;
            entry.remove("delegationMode");
            entry.remove("delegationPreference");
            entry.remove("frozenModel");
            entry.remove("explicitlyClosed");
        }
        tokio::fs::write(paths.catalog_file(), toml::to_string(&catalog)?).await?;
        let upgraded = StudioStore::open(paths.database()).await?;
        assert_eq!(
            database_schema_version(upgraded.database()).await?,
            STUDIO_DATABASE_SCHEMA_VERSION
        );
        let kept: pl_protocol::Thread = upgraded
            .read_thread("kept-thread")
            .await?
            .context("kept directory")?
            .into();
        assert_eq!(kept, old);
        let durable_catalog: toml::Table =
            toml::from_str(&tokio::fs::read_to_string(paths.catalog_file()).await?)?;
        assert_eq!(durable_catalog["schemaVersion"].as_integer(), Some(4));

        let request = EvaluateAgentRequest {
            target: "kept-child".into(),
            expected_turn_id: "final-1".into(),
            expected_revision: 0,
            task_category: AgentTaskCategory::Coding,
            outcome: AgentEvaluationOutcome::Passed,
            quality: Some(4),
            instruction_following: Some(5),
            comment: "真实事务保存证据".into(),
        };
        let candidate = AgentEvaluation {
            agent_id: request.target.clone(),
            parent_agent_id: "kept-thread".into(),
            model: pl_protocol::studio::NewThreadModelRoute {
                account_id: "kept-account".into(),
                model_id: "kept-model".into(),
                effort: Some("high".into()),
            },
            profile_id: "executor".into(),
            mode: Default::default(),
            preference: Default::default(),
            turn_id: request.expected_turn_id.clone(),
            revision: 0,
            task_category: request.task_category,
            outcome: request.outcome,
            quality: request.quality,
            instruction_following: request.instruction_following,
            comment: request.comment.clone(),
            created_at: 31,
            updated_at: 31,
        };
        let first = upgraded
            .write_agent_evaluation(&request, candidate.clone())
            .await?;
        upgraded
            .database()
            .execute_unprepared(
                "CREATE TRIGGER evaluation_write_failure BEFORE UPDATE ON agent_evaluations
            BEGIN SELECT RAISE(ABORT, 'injected evaluation persistence failure'); END;",
            )
            .await?;
        let mut next = request.clone();
        next.expected_turn_id = "final-2".into();
        next.expected_revision = first.evaluation.revision;
        let mut updated = candidate;
        updated.turn_id = next.expected_turn_id.clone();
        updated.updated_at = 32;
        let error = upgraded
            .write_agent_evaluation(&next, updated)
            .await
            .unwrap_err();
        assert!(format!("{error:#}").contains("injected evaluation persistence failure"));
        assert_eq!(
            upgraded.read_agent_evaluation("kept-child").await?,
            Some(first.evaluation.clone())
        );
        upgraded
            .database()
            .execute_unprepared("DROP TRIGGER evaluation_write_failure")
            .await?;
        upgraded.close().await?;
        drop(upgraded);
        let reopened = StudioStore::open(paths.database()).await?;
        assert_eq!(
            reopened.read_agent_evaluation("kept-child").await?,
            Some(first.evaluation)
        );
        assert_eq!(
            reopened
                .read_thread("kept-thread")
                .await?
                .context("kept Thread")?
                .title,
            old.title
        );
        reopened.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn schema_22_to_25_preserves_threads_and_keeps_unknown_facts_null() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let database = paths.database();
        tokio::fs::create_dir_all(database.parent().expect("database parent")).await?;
        let store = StudioStore::open(&database).await?;
        let mut delta = DirectoryDelta::upsert_project(ProjectDirectoryRecord {
            id: "project-1".into(),
            kind: pl_protocol::studio::WorkspaceKind::Project,
            name: "Project".into(),
            path: "/tmp/project".into(),
            ssh_alias: None,
            created_at: 1,
            updated_at: 1,
            last_opened_at: None,
            closed: false,
        });
        let (thread_delta, thread) = DirectoryDelta::register_root_thread(
            "thread-old".into(),
            "project-1",
            "旧会话",
            pl_protocol::ThreadModeId::simple(),
            pl_protocol::ThreadWorkspaceMode::Local,
            "/tmp/project".into(),
        );
        delta.thread_upserts = thread_delta.thread_upserts;
        let tx = store.database().begin().await?;
        apply_directory_delta(&store, &tx, &delta).await?;
        tx.commit().await?;
        // 把刚初始化的当前库降回上一版本：删除新列即得到与 v22 逐字一致的表结构。
        store
            .database()
            .execute_unprepared(
                "ALTER TABLE threads DROP COLUMN last_user_message_at;
                ALTER TABLE threads DROP COLUMN delegation_mode;
                ALTER TABLE threads DROP COLUMN delegation_preference;
                ALTER TABLE threads DROP COLUMN frozen_model_json;
                ALTER TABLE threads DROP COLUMN explicitly_closed;
                DROP TABLE agent_evaluations;",
            )
            .await?;
        store
            .database()
            .execute_unprepared("DROP TABLE IF EXISTS seaql_migrations; PRAGMA user_version=22")
            .await?;
        assert_eq!(
            database_schema_version(store.database()).await?,
            UPGRADEABLE_STUDIO_DATABASE_SCHEMA_VERSION
        );
        // Fail the delegation DDL after its ALTERs. Its entire step and completion record must
        // roll back, while the preceding directory-field migration remains committed for retry.
        store
            .database()
            .execute_unprepared("CREATE TABLE agent_evaluations(unrelated INTEGER)")
            .await?;
        store.close().await?;
        let failure = match StudioStore::open(&database).await {
            Ok(_) => anyhow::bail!("conflicting legacy DDL was accepted"),
            Err(error) => error,
        };
        assert!(format!("{failure:#}").contains("m20261026_000003_product_delegation"));
        let probe = connect_read_only_database(&database).await?;
        assert_eq!(database_schema_version(&probe).await?, 23);
        assert!(
            !sea_orm_migration::SchemaManager::new(&probe)
                .has_column("threads", "delegation_mode")
                .await?
        );
        assert!(probe.query_one_raw(Statement::from_string(DatabaseBackend::Sqlite,
            "SELECT version FROM seaql_migrations WHERE version='m20261026_000003_product_delegation'"))
            .await?.is_none());
        probe.close().await?;
        let probe = connect_sqlite(
            sqlite_file_options(&database, SqliteFileMode::ReadWrite, |options| options).await?,
            1,
        )
        .await?;
        probe
            .execute_unprepared("DROP TABLE agent_evaluations")
            .await?;
        probe.close().await?;

        // 重新打开：从已提交步骤接续原地升级，并校验 canonical 指纹与业务事实。
        let upgraded = StudioStore::open(&database).await?;
        assert_eq!(
            database_schema_version(upgraded.database()).await?,
            STUDIO_DATABASE_SCHEMA_VERSION
        );
        let record = upgraded
            .read_thread("thread-old")
            .await?
            .expect("upgraded store kept the v22 thread row");
        assert_eq!(record.id, thread.id);
        assert_eq!(record.title, "旧会话");
        // 旧目录缺失最近用户消息时间：迁移为缺失值，不以普通更新时间伪造。
        assert_eq!(record.updated_at, thread.updated_at);
        assert_eq!(record.last_user_message_at, None);
        assert_eq!(
            upgraded
                .catalog()
                .get("thread-old")
                .map(|entry| entry.last_user_message_at),
            Some(None),
        );

        // 升级幂等：再次打开不需要任何迁移步骤。
        drop(upgraded);
        let reopened = StudioStore::open(&database).await?;
        assert!(reopened.read_thread("thread-old").await?.is_some());
        Ok(())
    }
}

use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail, ensure};
use sha2::{Digest, Sha256};

use crate::config::STUDIO_CONFIG_DIR_NAME;

const STUDIO_DIR_NAME: &str = "studio";
const SESSION_LAYOUT_VERSION: &str = "v2";
const DATABASE_FILE_NAME: &str = "studio.sqlite";
const SKILLS_DIR_NAME: &str = "skills";
const SYSTEM_SKILLS_DIR_NAME: &str = ".system";
const STUDIO_HOME_ENV: &str = "ANYWORK_HOME";
const CALLS_FILE_NAME: &str = "calls.sqlite";
const SETTINGS_FILE_NAME: &str = "settings.toml";
const WORKSPACES_FILE_NAME: &str = "workspaces.toml";
const CATALOG_FILE_NAME: &str = "catalog.toml";
const PROJECTS_DIR_NAME: &str = "projects";
const SESSIONS_DIR_NAME: &str = "sessions";
const BOTS_DIR_NAME: &str = "bots";
const CALLS_DIR_NAME: &str = "calls";
const MIGRATIONS_DIR_NAME: &str = "migrations";
const ATTACHMENT_DRAFTS_DIR_NAME: &str = "attachment-drafts";
const HISTORY_FILE_NAME: &str = "history.sqlite";
const ATTACHMENTS_FILE_NAME: &str = "attachments.toml";
const BLOBS_DIR_NAME: &str = "blobs";
const RESOURCES_DIR_NAME: &str = "thread-resources";
const SCRATCH_DIR_NAME: &str = "scratch";
const ACP_PROBE_DIR_NAME: &str = "acp-probe";
/// 官方 ACP server 安装根目录名；与数据根同级隔离，不进入用户项目。
const ACP_SERVERS_DIR_NAME: &str = "acp-servers";
const PROJECT_MANIFEST_FILE_NAME: &str = "project.toml";
const SESSION_MANIFEST_FILE_NAME: &str = "session.toml";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StudioPaths {
    home: PathBuf,
    data_dir: PathBuf,
}

impl StudioPaths {
    pub fn resolve(explicit_home: Option<PathBuf>) -> Result<Self> {
        let home = match explicit_home {
            Some(home) => validate_studio_home(home, "--studio-home")?,
            None => match std::env::var_os(STUDIO_HOME_ENV) {
                Some(home) => validate_studio_home(PathBuf::from(home), STUDIO_HOME_ENV)?,
                None => user_home_dir()?.join(STUDIO_CONFIG_DIR_NAME),
            },
        };
        Ok(Self {
            data_dir: home.join(STUDIO_DIR_NAME).join(SESSION_LAYOUT_VERSION),
            home,
        })
    }

    pub fn home(&self) -> &Path {
        &self.home
    }

    pub fn database(&self) -> PathBuf {
        self.data_dir.join(DATABASE_FILE_NAME)
    }

    pub fn runtime_lock(&self) -> PathBuf {
        self.home.join(STUDIO_DIR_NAME).join("runtime.lock")
    }

    /// Returns the product-owned directory materialized from bundled system Skills.
    pub fn system_skills_dir(&self) -> PathBuf {
        self.home
            .join(STUDIO_DIR_NAME)
            .join(SKILLS_DIR_NAME)
            .join(SYSTEM_SKILLS_DIR_NAME)
    }
}

/// Layout entry points fixed by `design/17` §17.1.
///
/// Every slice (store, config, catalog) resolves its location here instead of
/// re-deriving names.
impl StudioPaths {
    /// Product and UI settings store.
    pub fn settings_file(&self) -> PathBuf {
        self.versioned_home().join(SETTINGS_FILE_NAME)
    }

    /// Project/Workspace definitions and stable references.
    pub fn workspaces_file(&self) -> PathBuf {
        self.versioned_home().join(WORKSPACES_FILE_NAME)
    }

    /// Lightweight Thread directory summaries consumed by the first screen.
    pub fn catalog_file(&self) -> PathBuf {
        self.versioned_home().join(CATALOG_FILE_NAME)
    }

    /// Config runtime path view for the same product home.
    ///
    /// `config.toml` and `agents/*.toml` are product files under the resolved Studio home; the
    /// config runtime consumes this view instead of re-deriving the layout.
    pub fn config_paths(&self) -> crate::config::ConfigPaths {
        crate::config::ConfigPaths::from_config_dir(self.home.clone())
    }

    /// Independent robot management root under the v2 data home.
    pub fn bots_dir(&self) -> PathBuf {
        self.versioned_home().join(BOTS_DIR_NAME)
    }

    /// Stable on-disk directory for one robot.
    pub fn bot_dir(&self, bot_id: &str) -> PathBuf {
        self.bots_dir().join(bot_id)
    }

    /// Canonical project roots: `v2/projects/<project-key>/`.
    pub fn projects_dir(&self) -> PathBuf {
        self.versioned_home().join(PROJECTS_DIR_NAME)
    }

    /// Pre-layout-migration session root: `v2/sessions/<thread-key>/`.
    ///
    /// Normal reads never create this directory. Migration consumes it and leaves unknown
    /// orphans in place.
    pub fn legacy_sessions_dir(&self) -> PathBuf {
        self.versioned_home().join(SESSIONS_DIR_NAME)
    }

    /// Global per-call record directory (`calls.sqlite` plus blob references).
    pub fn calls_dir(&self) -> PathBuf {
        self.versioned_home().join(CALLS_DIR_NAME)
    }

    /// Global, disposable call statistics database.
    pub fn calls_database(&self) -> PathBuf {
        self.calls_dir().join(CALLS_FILE_NAME)
    }

    /// Version-local migration state and consistent backups.
    pub fn migrations_dir(&self) -> PathBuf {
        self.versioned_home().join(MIGRATIONS_DIR_NAME)
    }

    /// Temporary attachment-draft root. Persistent attachments live under the owning Thread's
    /// `blobs` directory; this root is never an attachment catalog or content-addressed store.
    pub fn attachment_drafts_dir(&self) -> PathBuf {
        self.data_dir.join(ATTACHMENT_DRAFTS_DIR_NAME)
    }

    /// ACP 认证探测工作区根：产品数据根下按接入稳定 key 隔离，不使用用户项目目录。
    ///
    /// 目录只作为外部 Agent 的空 `cwd`；它不承载凭据、会话历史或供应商状态，删除它不撤销
    /// 官方程序的登录（见 design/17、design/28）。
    pub fn acp_probe_root(&self) -> PathBuf {
        self.data_dir.join(ACP_PROBE_DIR_NAME)
    }

    /// 一条接入专属的空探测目录；key 只由稳定接入 ID 派生。
    pub fn acp_probe_dir(&self, account_id: &str) -> Result<PathBuf> {
        Ok(self
            .acp_probe_root()
            .join(storage_key(account_id, "ACP account")?))
    }

    /// 官方 ACP server 安装根：`<Studio home>/studio/acp-servers`。
    ///
    /// 与会话版本数据根（`studio/v2`）、空探测 cwd、更新安装器缓存和会话 scratch 隔离；下载、
    /// 私有 staging、锁与已发布安装都在该根下按 provider/target/安装身份分层。它不绑定账号，
    /// 删除账号不删除资产（见 design/17、design/28 §28.5–28.7）。
    pub fn acp_servers_root(&self) -> PathBuf {
        self.home.join(STUDIO_DIR_NAME).join(ACP_SERVERS_DIR_NAME)
    }

    /// Stable on-disk directory for one Project.
    pub fn project_dir(&self, project_id: &str) -> Result<PathBuf> {
        Ok(self
            .projects_dir()
            .join(storage_key(project_id, "Project")?))
    }

    /// Versioned project identity manifest.
    pub fn project_manifest(&self, project_id: &str) -> Result<PathBuf> {
        Ok(self
            .project_dir(project_id)?
            .join(PROJECT_MANIFEST_FILE_NAME))
    }

    /// Typed session paths from an explicit Project and Thread identity.
    ///
    /// Unknown Threads must not be resolved by guessing a default Project. Callers that already
    /// hold both identities (child prepare, writer, tests) use this entry; registered Threads go
    /// through [`StudioStore::registered_session_paths`](crate::studio::store::StudioStore::registered_session_paths).
    pub fn session_paths(&self, project_id: &str, thread_id: &str) -> Result<SessionPaths> {
        SessionPaths::bind(self, project_id, thread_id)
    }

    /// Legacy flat session directory for one Thread key. Used by layout migration tests.
    #[cfg(test)]
    pub fn legacy_thread_dir(&self, thread_id: &str) -> Result<PathBuf> {
        Ok(self
            .legacy_sessions_dir()
            .join(storage_key(thread_id, "Thread")?))
    }

    fn versioned_home(&self) -> PathBuf {
        self.home.join(SESSION_LAYOUT_VERSION)
    }
}

/// Bound host paths for one Project + Thread pair.
///
/// The layout is
/// `v2/projects/<sha256(project_id)>/sessions/<sha256(thread_id)>/`.
/// Keys are stable identity digests, never path, alias, or display name.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionPaths {
    project_id: String,
    thread_id: String,
    root: PathBuf,
}

impl SessionPaths {
    fn bind(paths: &StudioPaths, project_id: &str, thread_id: &str) -> Result<Self> {
        let project_key = storage_key(project_id, "Project")?;
        let thread_key = storage_key(thread_id, "Thread")?;
        Ok(Self {
            project_id: project_id.to_owned(),
            thread_id: thread_id.to_owned(),
            root: paths
                .projects_dir()
                .join(project_key)
                .join(SESSIONS_DIR_NAME)
                .join(thread_key),
        })
    }

    pub fn project_id(&self) -> &str {
        &self.project_id
    }

    pub fn thread_id(&self) -> &str {
        &self.thread_id
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn history_database(&self) -> PathBuf {
        self.root.join(HISTORY_FILE_NAME)
    }

    pub fn attachments_catalog(&self) -> PathBuf {
        self.root.join(ATTACHMENTS_FILE_NAME)
    }

    pub fn blobs_dir(&self) -> PathBuf {
        self.root.join(BLOBS_DIR_NAME)
    }

    pub fn resources_dir(&self) -> PathBuf {
        self.root.join(RESOURCES_DIR_NAME)
    }

    /// Host-owned transfer scratch. Execution scratch lives in the workspace, not here.
    pub fn scratch_dir(&self) -> PathBuf {
        self.root.join(SCRATCH_DIR_NAME)
    }

    pub fn session_manifest(&self) -> PathBuf {
        self.root.join(SESSION_MANIFEST_FILE_NAME)
    }
}

/// Stable on-disk key for a Project or Thread directory.
pub fn storage_key(id: &str, kind: &str) -> Result<String> {
    ensure!(!id.is_empty(), "{kind} identity must not be empty");
    Ok(hex::encode(Sha256::digest(id.as_bytes())))
}

/// Stable on-disk key for a Thread session directory.
#[cfg(test)]
pub fn thread_storage_key(thread_id: &str) -> Result<String> {
    storage_key(thread_id, "Thread")
}

pub fn default_db_path() -> Result<PathBuf> {
    Ok(StudioPaths::resolve(None)?.database())
}

fn user_home_dir() -> Result<PathBuf> {
    #[cfg(windows)]
    const HOME_VARS: &[&str] = &["USERPROFILE", "HOME"];
    #[cfg(not(windows))]
    const HOME_VARS: &[&str] = &["HOME", "USERPROFILE"];

    HOME_VARS
        .iter()
        .filter_map(std::env::var_os)
        .map(PathBuf::from)
        .find(|path| !path.as_os_str().is_empty())
        .context("could not resolve user home directory")
}

fn validate_studio_home(path: PathBuf, source: &str) -> Result<PathBuf> {
    if path.as_os_str().is_empty() {
        anyhow::bail!("{source} must not be empty when configured");
    }
    if !path.is_absolute() {
        anyhow::bail!("{source} must be an absolute path");
    }
    Ok(path)
}

pub(crate) enum SqliteFileMode {
    ReadOnly,
    ReadWrite,
    Create,
}

/// Keeps filesystem names out of URI parsing and preserves native canonical prefixes.
/// Parent creation belongs to writers; this boundary never creates a directory or database.
pub(crate) async fn sqlite_file_options(
    path: &Path,
    mode: SqliteFileMode,
    configure: impl Fn(
        sea_orm::sqlx::sqlite::SqliteConnectOptions,
    ) -> sea_orm::sqlx::sqlite::SqliteConnectOptions
    + Send
    + Sync
    + 'static,
) -> Result<sea_orm::ConnectOptions> {
    let parent = path
        .parent()
        .context("SQLite database path has no parent")?;
    let filename = path
        .file_name()
        .context("SQLite database path has no filename")?;
    let native = tokio::fs::canonicalize(parent).await?.join(filename);
    let mut options = sea_orm::ConnectOptions::new("sqlite:");
    // SeaORM keeps one mapper. Compose the native filename and each store's tuning here.
    options.map_sqlx_sqlite_opts(move |options| {
        configure(
            options
                .filename(&native)
                .read_only(matches!(mode, SqliteFileMode::ReadOnly))
                .create_if_missing(matches!(mode, SqliteFileMode::Create)),
        )
    });
    Ok(options)
}

pub fn project_name(path: &Path) -> String {
    path.file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.trim().is_empty())
        .map(ToOwned::to_owned)
        .unwrap_or_else(|| path.display().to_string())
}

pub(crate) fn posix_relative(path: &Path) -> Result<String> {
    let mut parts = Vec::new();
    for component in path.components() {
        match component {
            std::path::Component::Normal(part) => {
                let part = part.to_str().context("path component is not UTF-8")?;
                ensure!(
                    part != "." && part != ".." && !part.contains('/'),
                    "unsafe relative path component"
                );
                parts.push(part);
            }
            _ => bail!("attachment path must be a safe session-relative reference"),
        }
    }
    ensure!(!parts.is_empty(), "attachment path must not be empty");
    Ok(parts.join("/"))
}

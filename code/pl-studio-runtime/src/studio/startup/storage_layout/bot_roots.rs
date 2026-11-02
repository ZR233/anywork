//! Exact bot root relocations, retained as migration evidence, never as an execution fallback.
use super::*;
use crate::studio::catalog::CatalogEntry;
use sea_orm::{ConnectionTrait, Database, DatabaseBackend, DatabaseConnection, Statement};

/// Compare recorded addresses without resolving a source already moved to backup.
/// Only safely removable Windows verbatim prefixes are ignored; other spelling
/// differences must not grant authority to relocate an execution binding.
pub(in crate::studio) fn same_path(left: &Path, right: &Path) -> bool {
    dunce::simplified(left).as_os_str() == dunce::simplified(right).as_os_str()
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct BotRootMove {
    pub(crate) bot_id: String,
    pub(crate) workspace_id: String,
    pub(crate) old_root: String,
    pub(crate) new_root: String,
    pub(crate) threads: BTreeMap<String, ThreadMove>,
    pub(crate) blocked: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct ThreadMove {
    pub(crate) proven_local_root: bool,
    pub(crate) diagnostic: Option<String>,
}
pub(super) async fn plan(
    paths: &StudioPaths,
    stage: &StudioPaths,
    roots: &[PathBuf],
    catalog: &CatalogStore,
) -> Result<Vec<BotRootMove>> {
    let mut result = Vec::new();
    let mut assigned = BTreeSet::new();
    for root in roots {
        let bots = root.join("bots");
        if !bots.try_exists()? {
            continue;
        }
        for directory in std::fs::read_dir(&bots)? {
            let directory = directory?;
            if !directory.file_type()?.is_dir() {
                continue;
            }
            let config_path = directory.path().join("config.toml");
            if !config_path.try_exists()? {
                continue;
            } // unregistered entries are preserved, not claimed
            let config = crate::bots::load_config(&config_path)?;
            ensure!(
                directory.file_name().to_str() == Some(config.id.as_str()),
                "bot directory/config identity conflict"
            );
            let original = original_path(paths, &directory.path())?;
            let old_root = original
                .join("workspace")
                .to_str()
                .context("bot root is not UTF-8")?
                .to_owned();
            let new_root = paths
                .bot_dir(&config.id)
                .join("workspace")
                .to_str()
                .context("bot root is not UTF-8")?
                .to_owned();
            let ledger = stage.bot_dir(&config.id).join("state.sqlite");
            let bindings = if ledger.try_exists()? {
                bindings(&ledger).await?
            } else {
                Vec::new()
            };
            let mut threads = BTreeMap::new();
            for (thread, owner) in bindings {
                ensure!(
                    owner == config.workspace_id,
                    "bot binding/config Workspace conflict"
                );
                let parent = catalog
                    .get(&thread)
                    .context("bot binding references a missing catalog root")?;
                ensure!(
                    parent.workspace_id == config.workspace_id && parent.parent_thread_id.is_none(),
                    "bot binding does not own a catalog root"
                );
                for entry in catalog
                    .entries()
                    .into_iter()
                    .filter(|entry| entry.root_thread_id == thread)
                {
                    ensure!(
                        assigned.insert(entry.id.clone()),
                        "Thread is bound to multiple bots"
                    );
                    let source = source_session(roots, &entry)?;
                    let proof = stage
                        .home()
                        .join("bot-proofs")
                        .join(storage_key(&entry.id, "Thread")?);
                    let frozen = if let Some(source) = &source {
                        read_frozen_owner(paths.home(), source, &proof, &entry.id).await?
                    } else {
                        None
                    };
                    if let Some(frozen) = &frozen {
                        ensure!(
                            frozen == &config.id,
                            "bot ledger/checkpoint ownership conflict"
                        );
                    }
                    let diagnostic = if frozen.is_none() {
                        Some("bot checkpoint has no stable owner evidence; execution binding was preserved".into())
                    } else if entry.workspace_mode != pl_protocol::ThreadWorkspaceMode::Local
                        || !same_path(Path::new(&entry.workspace_path), Path::new(&old_root))
                    {
                        Some("bot execution binding is not the exact local managed root; original execution address was preserved".into())
                    } else {
                        None
                    };
                    threads.insert(
                        entry.id,
                        ThreadMove {
                            proven_local_root: diagnostic.is_none(),
                            diagnostic,
                        },
                    );
                }
            }
            result.push(BotRootMove {
                bot_id: config.id,
                workspace_id: config.workspace_id,
                old_root,
                new_root,
                threads,
                blocked: BTreeMap::new(),
            });
        }
    }
    result.sort_by(|left, right| left.bot_id.cmp(&right.bot_id));
    ensure!(
        result
            .windows(2)
            .all(|pair| pair[0].bot_id != pair[1].bot_id),
        "duplicate bot roots"
    );
    Ok(result)
}

fn source_session(roots: &[PathBuf], entry: &CatalogEntry) -> Result<Option<PathBuf>> {
    let thread = storage_key(&entry.id, "Thread")?;
    let owner = storage_key(&entry.workspace_id, "Workspace")?;
    let mut found = Vec::new();
    for root in roots {
        for path in [
            root.join("projects")
                .join(&owner)
                .join("sessions")
                .join(&thread),
            root.join("sessions").join(&thread),
        ] {
            if path.try_exists()? {
                found.push(path);
            }
        }
    }
    ensure!(found.len() <= 1, "ambiguous bot session source");
    Ok(found.pop())
}
async fn read_only(path: &Path) -> Result<DatabaseConnection> {
    use crate::studio::paths::{SqliteFileMode, sqlite_file_options};
    let mut options =
        sqlite_file_options(path, SqliteFileMode::ReadOnly, |options| options).await?;
    options
        .max_connections(1)
        .min_connections(1)
        .sqlx_logging(false);
    Ok(Database::connect(options).await?)
}
async fn bindings(path: &Path) -> Result<Vec<(String, String)>> {
    let db = read_only(path).await?;
    let result = async {
        let row = db.query_one_raw(sql("SELECT schema_version FROM bot_meta WHERE id=1")).await?.context("missing bot ledger version")?;
        let version: i64 = row.try_get_by_index(0)?;
        ensure!((1..=7).contains(&version), "unsupported bot ledger version");
        let owner = if version < 7 { "project_id" } else { "workspace_id" };
        let query = format!("SELECT thread_id,{owner} AS owner FROM thread_bindings WHERE status='bound' AND thread_id IS NOT NULL ORDER BY thread_id");
        db.query_all_raw(sql(query)).await?.into_iter().map(|row| Ok((row.try_get("", "thread_id")?, row.try_get("", "owner")?))).collect::<Result<Vec<_>>>()
    }.await;
    let closed = db.close().await;
    let value = result?;
    closed?;
    Ok(value)
}
fn sql(query: impl Into<String>) -> Statement {
    Statement::from_string(DatabaseBackend::Sqlite, query)
}

async fn read_frozen_owner(
    home: &Path,
    source: &Path,
    proof: &Path,
    thread_id: &str,
) -> Result<Option<String>> {
    // Query a disposable copy, never the preserved SQLite family: even a read-only SQLite handle
    // can update its SHM coordination bytes.
    let history = source.join("history.sqlite");
    validate_family(&history)?;
    let committed = if history.try_exists()? {
        if !proof.join("copied").try_exists()? {
            for suffix in ["", "-wal", "-shm"] {
                let from = source.join(format!("history.sqlite{suffix}"));
                if from.try_exists()? {
                    copy_tree(home, &from, &proof.join(format!("history.sqlite{suffix}"))).await?;
                }
            }
            session_layout::write_manifest(&proof.join("copied"), "copied\n").await?;
        }
        let db = read_only(&proof.join("history.sqlite")).await?;
        let result = async {
            crate::studio::storage::history::validate_layout_source(&db, thread_id).await?;
            // Supported early schemas can predate the checkpoint table. The official preflight
            // above, not table absence alone, proves whether that layout is legitimate.
            if db
                .query_one_raw(sql(
                    "SELECT name FROM sqlite_schema WHERE type='table' AND name='session_checkpoint'",
                ))
                .await?
                .is_none()
            {
                return Ok(None);
            }
            let Some(row) = db
                .query_one_raw(sql(
                    "SELECT payload,payload_hash FROM session_checkpoint WHERE id=1",
                ))
                .await?
            else {
                return Ok(None);
            };
            let payload: String = row.try_get("", "payload")?;
            ensure!(
                pl_core::context::content_hash(payload.as_bytes())
                    == row.try_get::<String>("", "payload_hash")?,
                "bot checkpoint hash mismatch"
            );
            Ok::<_, anyhow::Error>(Some(serde_json::from_str::<serde_json::Value>(&payload)?))
        }
        .await;
        let closed = db.close().await;
        let value = result?;
        closed?;
        value
    } else {
        None
    };
    // Only a committed SQLite checkpoint supersedes TOML. Schema creation can precede import;
    // use the recovery owner's frozen DTO/materialization rules in that explicit migration window.
    let payload = match committed {
        Some(payload) => Some(payload),
        None => crate::studio::storage::state::StateStore::new(source.to_owned(), thread_id)
            .load_legacy()
            .await?
            .map(serde_json::to_value)
            .transpose()?,
    };
    let Some(payload) = payload else {
        return Ok(None);
    };
    ensure!(
        payload.get("threadId").and_then(serde_json::Value::as_str) == Some(thread_id),
        "bot checkpoint Thread mismatch"
    );
    let Some(owner) = payload.pointer("/state/extensions/studio.bot-owner") else {
        return Ok(None);
    };
    let extension: pl_core::thread::extensions::ExtensionRecord =
        serde_json::from_value(owner.clone())?;
    ensure!(
        extension.payload.format() == "pl.studio.bot-owner" && extension.payload.version() == 1,
        "unsupported saved bot owner"
    );
    let id: String = serde_json::from_str(extension.payload.content())?;
    crate::bots::validate_bot_id(&id)?;
    Ok(Some(id))
}

pub(crate) async fn for_history(database: &Path, thread_id: &str) -> Result<Option<BotRootMove>> {
    let Some(paths) = StudioPaths::from_session_database(database, thread_id)? else {
        return Ok(None);
    };
    let path = paths.home().join(JOURNAL);
    session_layout::safe_path(&paths, &path).await?;
    let Some(content) = optional_text(&path).await? else {
        return Ok(None);
    };
    let record = decode_journal(&content)?;
    ensure!(
        matches!(record.phase, Phase::Publishing | Phase::Completed),
        "bot root migration has not been published"
    );
    let mut result = None;
    for item in record.bot_roots {
        item.validate(&paths)?;
        if item.threads.contains_key(thread_id) {
            ensure!(
                paths
                    .session_paths(&item.workspace_id, thread_id)?
                    .history_database()
                    == database,
                "bot migration Workspace/Thread path mismatch"
            );
            ensure!(result.is_none(), "duplicate bot Thread mapping");
            result = Some(item);
        }
    }
    Ok(result)
}

/// The physical files may still be in staging; their recorded addresses are final paths.
pub(super) async fn migrate_workspace_completions(
    paths: &StudioPaths,
    target: &StudioPaths,
    mappings: &[BotRootMove],
) -> Result<()> {
    let mut bots = BTreeSet::new();
    let mut threads = BTreeSet::new();
    // Validate all ownership evidence before the first file is changed.
    for mapping in mappings {
        mapping.validate(paths)?;
        ensure!(bots.insert(&mapping.bot_id), "duplicate bot root mapping");
        for thread in mapping.threads.keys() {
            ensure!(threads.insert(thread), "duplicate bot Thread mapping");
        }
    }
    for mapping in mappings {
        for (thread, proof) in &mapping.threads {
            if !proof.proven_local_root || mapping.blocked.contains_key(thread) {
                continue;
            }
            let files = pl_tool::workspace::SessionFiles::new(thread);
            let marker = target
                .bot_dir(&mapping.bot_id)
                .join("workspace")
                .join(files.root())
                .join(".migration-complete");
            session_layout::safe_path(target, &marker).await?;
            let content = match tokio::fs::read(&marker).await {
                Ok(content) => content,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
                Err(error) => {
                    return Err(error)
                        .with_context(|| format!("read bot workspace completion for {thread}"));
                }
            };
            let old = Path::new(&mapping.old_root).join(files.root());
            let current = Path::new(&mapping.new_root).join(files.root());
            if std::str::from_utf8(&content).is_ok_and(|content| {
                same_path(Path::new(content), &old) || same_path(Path::new(content), &current)
            }) {
                // A prior atomic replacement may have applied before its sync failed.
                // Reconfirm that write before advancing the layout version on a retry.
                session_layout::write_manifest(&marker, &current.to_string_lossy())
                    .await
                    .with_context(|| format!("relocate bot workspace completion for {thread}"))?;
            }
        }
    }
    Ok(())
}

impl BotRootMove {
    fn validate(&self, paths: &StudioPaths) -> Result<()> {
        crate::bots::validate_bot_id(&self.bot_id)?;
        ensure!(
            same_path(
                Path::new(&self.new_root),
                &paths.bot_dir(&self.bot_id).join("workspace")
            ),
            "bot migration destination identity mismatch"
        );
        let expected = [
            paths
                .home()
                .join("v2/bots")
                .join(&self.bot_id)
                .join("workspace"),
            paths
                .home()
                .join("studio/v2/bots")
                .join(&self.bot_id)
                .join("workspace"),
        ];
        ensure!(
            expected
                .iter()
                .any(|old| same_path(old, Path::new(&self.old_root))),
            "bot migration source identity mismatch"
        );
        ensure!(
            self.blocked
                .keys()
                .all(|thread| self.threads.contains_key(thread)),
            "bot migration diagnostic has no proven owner"
        );
        ensure!(
            self.threads
                .values()
                .all(|proof| proof.proven_local_root == proof.diagnostic.is_none()),
            "bot root migration proof/diagnostic conflict"
        );
        Ok(())
    }

    pub(crate) fn require_convertible(&self, thread_id: &str) -> Result<()> {
        let proof = self
            .threads
            .get(thread_id)
            .context("bot migration does not own the Thread")?;
        ensure!(
            proof.proven_local_root && proof.diagnostic.is_none(),
            "{}",
            proof
                .diagnostic
                .as_deref()
                .unwrap_or("unreachable migration diagnostic")
        );
        ensure!(
            !self.blocked.contains_key(thread_id),
            "{}",
            self.blocked
                .get(thread_id)
                .map(String::as_str)
                .unwrap_or("unreachable bot migration diagnostic")
        );
        Ok(())
    }
    pub(crate) fn exact_path(&self, value: &mut String) -> Result<()> {
        ensure!(
            same_path(Path::new(value), Path::new(&self.old_root))
                || same_path(Path::new(value), Path::new(&self.new_root)),
            "bot execution address differs from both exact migration roots"
        );
        value.clone_from(&self.new_root);
        Ok(())
    }
}

//! Exact bot root relocations, retained as migration evidence, never as an execution fallback.
use super::*;
use crate::studio::catalog::CatalogEntry;
use sea_orm::{ConnectionTrait, Database, DatabaseBackend, DatabaseConnection, Statement};

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
                        || entry.workspace_path != old_root
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
    let payload = if history.try_exists()? {
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
            if db
                .query_one_raw(sql(
                    "SELECT name FROM sqlite_schema WHERE name='session_checkpoint'",
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
    } else if let Some(content) = optional_text(&source.join("state.toml")).await? {
        Some(serde_json::to_value(toml::from_str::<toml::Value>(
            &content,
        )?)?)
    } else {
        None
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
        crate::bots::validate_bot_id(&item.bot_id)?;
        ensure!(
            Path::new(&item.new_root) == paths.bot_dir(&item.bot_id).join("workspace"),
            "bot migration destination identity mismatch"
        );
        let expected = [
            paths
                .home()
                .join("v2/bots")
                .join(&item.bot_id)
                .join("workspace"),
            paths
                .home()
                .join("studio/v2/bots")
                .join(&item.bot_id)
                .join("workspace"),
        ];
        ensure!(
            expected.iter().any(|old| old == Path::new(&item.old_root)),
            "bot migration source identity mismatch"
        );
        ensure!(
            item.blocked
                .keys()
                .all(|thread| item.threads.contains_key(thread)),
            "bot migration diagnostic has no proven owner"
        );
        ensure!(
            item.threads
                .values()
                .all(|proof| proof.proven_local_root == proof.diagnostic.is_none()),
            "bot root migration proof/diagnostic conflict"
        );
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

impl BotRootMove {
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
        if *value == self.old_root {
            *value = self.new_root.clone();
        } else {
            ensure!(
                *value == self.new_root,
                "bot execution address differs from both exact migration roots"
            );
        }
        Ok(())
    }
}

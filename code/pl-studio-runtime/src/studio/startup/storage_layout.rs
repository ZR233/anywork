//! One locked, resumable v2 → current layout operation. Backups are never runtime fallback roots.
//!
//! Root moves preserve the complete SQLite families before any connection is opened. The operation
//! owns a staging home; individual copy steps are journaled before schema migration may mutate it.
//! Publication is one managed directory move after validation, not a cross-file SQL transaction.
use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, ensure};
use serde::{Deserialize, Serialize};

use crate::studio::paths::StudioPaths;
use crate::studio::store::{SessionLayoutMigrationFailed, StudioStore, session_layout};

const JOURNAL: &str = "storage-migration.toml";
const ROOTS: [&str; 3] = ["v2", "studio/v2", "skills"];
const LAYOUT_SCHEMA_VERSION: u32 = 2;
pub(crate) mod bot_roots;

mod build;
mod files;

pub(in crate::studio) use build::PreparedLayoutDatabase;
use build::build;
use files::ensure_tree_safe;

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Layout {
    schema_version: u32,
    operation_id: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum Phase {
    Preserving,
    Building,
    Publishing,
    Completed,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct RootMove {
    source: String,
    present: bool,
    moved: bool,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Journal {
    schema_version: u32,
    operation_id: String,
    phase: Phase,
    roots: Vec<RootMove>,
    copied: BTreeSet<String>,
    bot_roots: Vec<bot_roots::BotRootMove>,
}

/// Must run while the runtime lock is held, after startup recovery and before config/cache opening.
pub(crate) async fn prepare(paths: &StudioPaths) -> Result<()> {
    prepare_inner(paths)
        .await
        .map_err(|source| anyhow::Error::new(SessionLayoutMigrationFailed { source }))
}

async fn prepare_inner(paths: &StudioPaths) -> Result<()> {
    session_layout::safe_path(paths, &paths.layout_file()).await?;
    let journal_path = paths.home().join(JOURNAL);
    session_layout::safe_path(paths, &journal_path).await?;
    let journal = optional_text(&journal_path).await?;
    if let Some(content) = optional_text(&paths.layout_file()).await? {
        return resume_published(paths, &journal_path, &content, journal.as_deref()).await;
    }
    let mut journal = match journal {
        Some(content) => decode_journal(&content)?,
        None => start_journal(paths, &journal_path).await?,
    };
    let backup = backup_root(paths, &journal);
    session_layout::safe_path(paths, &backup).await?;
    preserve_sources(paths, &backup, &journal_path, &mut journal).await?;
    let stage = staging(paths, &journal);
    if journal.phase == Phase::Building {
        prepare_staging(paths, &stage, &backup, &journal_path, &mut journal).await?;
    }
    if journal.phase == Phase::Publishing {
        publish_staging(paths, &stage, &journal_path, &mut journal).await?;
    }
    ensure!(
        journal.phase == Phase::Completed && paths.layout_file().try_exists()?,
        "completed journal has no current layout"
    );
    Ok(())
}

async fn resume_published(
    paths: &StudioPaths,
    journal_path: &Path,
    content: &str,
    journal: Option<&str>,
) -> Result<()> {
    let layout: Layout = toml::from_str(content).context("invalid current layout marker")?;
    validate_layout(&layout)?;
    for path in [
        paths.database(),
        paths.catalog_file(),
        paths.settings_file(),
        paths.workspaces_file(),
        paths.calls_database(),
    ] {
        session_layout::safe_path(paths, &path).await?;
        ensure!(
            tokio::fs::metadata(&path)
                .await
                .context("current authoritative storage file is missing")?
                .is_file(),
            "invalid current storage file"
        );
    }
    let mut record = journal.map(decode_journal).transpose()?;
    if let Some(record) = &record {
        ensure!(
            record.operation_id == layout.operation_id
                && matches!(record.phase, Phase::Publishing | Phase::Completed),
            "layout marker conflicts with migration journal"
        );
        if record.phase == Phase::Publishing {
            ensure!(
                !staging(paths, record).data_dir().try_exists()?,
                "both staging and published layout exist"
            );
        }
    }
    upgrade_layout(paths, paths, &layout, record.as_ref()).await?;
    if let Some(record) = &mut record
        && record.phase == Phase::Publishing
    {
        record.phase = Phase::Completed;
        persist(journal_path, record).await?;
    }
    // No recursive scan of resources on normal startup.
    Ok(())
}

async fn start_journal(paths: &StudioPaths, journal_path: &Path) -> Result<Journal> {
    ensure!(
        !paths.data_dir().try_exists()?,
        "current data root has no authoritative layout marker; preserving it"
    );
    let mut roots = Vec::new();
    for source in ROOTS {
        let path = paths.home().join(source);
        session_layout::safe_path(paths, &path).await?;
        let present = match tokio::fs::symlink_metadata(&path).await {
            Ok(meta) => {
                ensure!(
                    meta.is_dir() && !pl_tool::workspace::path_safety::is_link_or_reparse(&meta),
                    "invalid migration source"
                );
                true
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => false,
            Err(error) => return Err(error.into()),
        };
        roots.push(RootMove {
            source: source.into(),
            present,
            moved: false,
        });
    }
    let record = Journal {
        schema_version: 1,
        operation_id: crate::studio::ids::new_id("layout"),
        phase: Phase::Preserving,
        roots,
        copied: BTreeSet::new(),
        bot_roots: Vec::new(),
    };
    persist(journal_path, &record).await?;
    Ok(record)
}

async fn preserve_sources(
    paths: &StudioPaths,
    backup: &Path,
    journal_path: &Path,
    journal: &mut Journal,
) -> Result<()> {
    if journal.phase == Phase::Preserving {
        for index in 0..journal.roots.len() {
            let item = &journal.roots[index];
            let source = paths.home().join(&item.source);
            let target = backup.join(&item.source);
            session_layout::safe_path(paths, &source).await?;
            session_layout::safe_path(paths, &target).await?;
            match (
                source.try_exists()?,
                target.try_exists()?,
                item.present,
                item.moved,
            ) {
                (false, false, false, false) => {}
                (true, false, true, false) => {
                    ensure_tree_safe(paths.home(), &source).await?;
                    managed_move(&source, &target).await?;
                }
                (false, true, true, _) => {
                    ensure_tree_safe(paths.home(), &target).await?;
                }
                _ => anyhow::bail!("ambiguous migration source/backup state: {}", item.source),
            }
            if item.present {
                journal.roots[index].moved = true;
                persist(journal_path, journal).await?;
            }
        }
        journal.phase = Phase::Building;
        persist(journal_path, journal).await?;
    }
    for item in &journal.roots {
        ensure!(
            !paths.home().join(&item.source).try_exists()?,
            "migration source reappeared after preservation"
        );
        ensure!(
            backup.join(&item.source).try_exists()? == item.present,
            "preserved migration root is missing or unexpected"
        );
    }
    Ok(())
}

async fn prepare_staging(
    paths: &StudioPaths,
    stage: &StudioPaths,
    backup: &Path,
    journal_path: &Path,
    journal: &mut Journal,
) -> Result<()> {
    ensure!(
        !paths.data_dir().try_exists()?,
        "unexpected current target during layout construction"
    );
    session_layout::safe_path(paths, stage.data_dir()).await?;
    tokio::fs::create_dir_all(stage.data_dir()).await?;
    let database = build(paths, stage, backup, journal_path, journal).await?;
    // This is the production loader and official SeaORM schema sequence, not a second decoder.
    // Every raw family copy has completed before this may open or checkpoint SQLite.
    let store = StudioStore::prepare_layout_database(database).await?;
    let relocated = async {
        crate::studio::worktree::worktree_lease::migrate_bot_identities(
            store.database(),
            &mut journal.bot_roots,
        )
        .await?;
        crate::studio::store::agent_close::migrate_bot_roots(
            store.database(),
            &mut journal.bot_roots,
        )
        .await
    }
    .await;
    let closed = store.close().await;
    relocated?;
    closed?;
    persist(journal_path, journal).await?;
    let marker = Layout {
        schema_version: 1,
        operation_id: journal.operation_id.clone(),
    };
    persist(&stage.layout_file(), &marker).await?;
    journal.phase = Phase::Publishing;
    persist(journal_path, journal).await?;
    Ok(())
}

async fn publish_staging(
    paths: &StudioPaths,
    stage: &StudioPaths,
    journal_path: &Path,
    journal: &mut Journal,
) -> Result<()> {
    let content = tokio::fs::read_to_string(stage.layout_file())
        .await
        .context("validated staging layout is missing")?;
    let marker: Layout = toml::from_str(&content)?;
    validate_layout(&marker)?;
    ensure!(
        marker.operation_id == journal.operation_id && !paths.data_dir().try_exists()?,
        "layout publication ownership conflict"
    );
    // An older application may have stopped after preparing a v1 staging layout.
    upgrade_layout(paths, stage, &marker, Some(journal)).await?;
    managed_move(stage.data_dir(), paths.data_dir()).await?;
    journal.phase = Phase::Completed;
    persist(journal_path, journal).await?;
    Ok(())
}

fn validate_layout(layout: &Layout) -> Result<()> {
    ensure!(
        (1..=LAYOUT_SCHEMA_VERSION).contains(&layout.schema_version)
            && valid_id(&layout.operation_id),
        "unsupported current data layout"
    );
    Ok(())
}

/// Finish the omitted completion-address move before publishing its content-layout version.
/// A published v1 installation uses its original journal, never its preserved source files.
async fn upgrade_layout(
    paths: &StudioPaths,
    target: &StudioPaths,
    layout: &Layout,
    journal: Option<&Journal>,
) -> Result<()> {
    if layout.schema_version == LAYOUT_SCHEMA_VERSION {
        return Ok(());
    }
    if let Some(journal) = journal {
        bot_roots::migrate_workspace_completions(paths, target, &journal.bot_roots).await?;
    }
    persist(
        &target.layout_file(),
        &Layout {
            schema_version: LAYOUT_SCHEMA_VERSION,
            operation_id: layout.operation_id.clone(),
        },
    )
    .await
}

fn decode_journal(content: &str) -> Result<Journal> {
    let record: Journal = toml::from_str(content)
        .context("invalid storage migration journal; preserving source and target")?;
    ensure!(
        record.schema_version == 1 && valid_id(&record.operation_id),
        "unsupported storage migration journal"
    );
    ensure!(
        record.roots.len() == ROOTS.len()
            && record
                .roots
                .iter()
                .zip(ROOTS)
                .all(|(item, expected)| item.source == expected && (!item.moved || item.present)),
        "migration root bindings changed"
    );
    ensure!(
        record.phase == Phase::Preserving
            || record.roots.iter().all(|item| item.moved == item.present),
        "migration backup progress is inconsistent"
    );
    Ok(record)
}

pub(crate) fn incomplete_operation(path: &Path) -> Result<bool> {
    match std::fs::read_to_string(path) {
        Ok(content) => Ok(decode_journal(&content)?.phase != Phase::Completed),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error.into()),
    }
}
fn valid_id(id: &str) -> bool {
    id.starts_with("layout-")
        && id.len() > 7
        && id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
}
fn backup_root(paths: &StudioPaths, journal: &Journal) -> PathBuf {
    paths
        .home()
        .join("migration-backups")
        .join(&journal.operation_id)
}
fn staging(paths: &StudioPaths, journal: &Journal) -> StudioPaths {
    StudioPaths::from_home(backup_root(paths, journal).join("current-home"))
}
async fn optional_text(path: &Path) -> Result<Option<String>> {
    match tokio::fs::read_to_string(path).await {
        Ok(content) => Ok(Some(content)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.into()),
    }
}
async fn persist(path: &Path, record: &impl Serialize) -> Result<()> {
    session_layout::write_manifest(path, &toml::to_string_pretty(record)?).await
}
async fn managed_move(source: &Path, target: &Path) -> Result<()> {
    let (source, target) = (source.to_owned(), target.to_owned());
    tokio::task::spawn_blocking(move || -> Result<()> {
        std::fs::create_dir_all(target.parent().context("migration target has no parent")?)?;
        pl_tool::workspace::move_owned_path(&source, &target)?;
        Ok(())
    })
    .await??;
    Ok(())
}

#[cfg(test)]
mod tests;

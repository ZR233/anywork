//! One locked, resumable v2 → current layout operation. Backups are never runtime fallback roots.
//!
//! Root moves preserve the complete SQLite families before any connection is opened. The operation
//! owns a staging home; individual copy steps are journaled before schema migration may mutate it.
//! Publication is one managed directory move after validation, not a cross-file SQL transaction.
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, ensure};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::studio::catalog::CatalogStore;
use crate::studio::paths::{StudioPaths, storage_key};
use crate::studio::store::{
    SessionLayoutMigrationFailed, StudioStore, attachment, session_layout, workspaces,
};
use session_layout::{SessionManifest, WorkspaceManifest};

const JOURNAL: &str = "storage-migration.toml";
const ROOTS: [&str; 3] = ["v2", "studio/v2", "skills"];
pub(crate) mod bot_roots;

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
pub(in crate::studio) async fn prepare(paths: &StudioPaths) -> Result<()> {
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
        let layout: Layout = toml::from_str(&content).context("invalid current layout marker")?;
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
        if let Some(content) = journal {
            let mut record = decode_journal(&content)?;
            ensure!(
                record.operation_id == layout.operation_id
                    && matches!(record.phase, Phase::Publishing | Phase::Completed),
                "layout marker conflicts with migration journal"
            );
            if record.phase == Phase::Publishing {
                ensure!(
                    !staging(paths, &record).data_dir().try_exists()?,
                    "both staging and published layout exist"
                );
                record.phase = Phase::Completed;
                persist(&journal_path, &record).await?;
            }
        }
        // No recursive scan of resources on normal startup.
        return Ok(());
    }
    let mut journal = match journal {
        Some(content) => decode_journal(&content)?,
        None => {
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
                            meta.is_dir()
                                && !pl_tool::workspace::path_safety::is_link_or_reparse(&meta),
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
            persist(&journal_path, &record).await?;
            record
        }
    };
    let backup = backup_root(paths, &journal);
    session_layout::safe_path(paths, &backup).await?;
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
                persist(&journal_path, &journal).await?;
            }
        }
        journal.phase = Phase::Building;
        persist(&journal_path, &journal).await?;
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
    let stage = staging(paths, &journal);
    if journal.phase == Phase::Building {
        ensure!(
            !paths.data_dir().try_exists()?,
            "unexpected current target during layout construction"
        );
        session_layout::safe_path(paths, stage.data_dir()).await?;
        tokio::fs::create_dir_all(stage.data_dir()).await?;
        build(paths, &stage, &backup, &journal_path, &mut journal).await?;
        // This is the production loader and official SeaORM schema sequence, not a second decoder.
        // Every raw family copy has completed before this may open or checkpoint SQLite.
        let store = StudioStore::prepare_database(&stage.database()).await?;
        let relocated = async {
            crate::studio::agent_host::worktree_lease::migrate_bot_identities(
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
        persist(&journal_path, &journal).await?;
        let marker = Layout {
            schema_version: 1,
            operation_id: journal.operation_id.clone(),
        };
        persist(&stage.layout_file(), &marker).await?;
        journal.phase = Phase::Publishing;
        persist(&journal_path, &journal).await?;
    }
    if journal.phase == Phase::Publishing {
        let content = tokio::fs::read_to_string(stage.layout_file())
            .await
            .context("validated staging layout is missing")?;
        let marker: Layout = toml::from_str(&content)?;
        validate_layout(&marker)?;
        ensure!(
            marker.operation_id == journal.operation_id && !paths.data_dir().try_exists()?,
            "layout publication ownership conflict"
        );
        managed_move(stage.data_dir(), paths.data_dir()).await?;
        journal.phase = Phase::Completed;
        persist(&journal_path, &journal).await?;
    }
    ensure!(
        journal.phase == Phase::Completed && paths.layout_file().try_exists()?,
        "completed journal has no current layout"
    );
    Ok(())
}

fn validate_layout(layout: &Layout) -> Result<()> {
    ensure!(
        layout.schema_version == 1 && valid_id(&layout.operation_id),
        "unsupported current data layout"
    );
    Ok(())
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

async fn build(
    paths: &StudioPaths,
    stage: &StudioPaths,
    backup: &Path,
    journal_path: &Path,
    journal: &mut Journal,
) -> Result<()> {
    let roots = [backup.join("v2"), backup.join("studio/v2")];
    let has_v2 = journal.roots.iter().take(2).any(|root| root.present);
    for name in ["settings.toml", "workspaces.toml", "catalog.toml"] {
        let candidates = existing_candidates(&roots, name)?;
        if has_v2 {
            ensure!(
                candidates.len() == 1,
                "v2 authoritative {name} missing or duplicated"
            );
        }
        if let Some(source) = candidates.first() {
            let content = tokio::fs::read_to_string(source).await?;
            let current = match name {
                "catalog.toml" => crate::studio::catalog::migrate_v2_content(source, &content)?,
                "workspaces.toml" => workspaces::migrate_v2_content(source, &content)?,
                _ => content,
            };
            session_layout::write_manifest(&stage.data_dir().join(name), &current).await?;
        }
    }
    for name in [
        "studio.sqlite",
        "calls",
        "model-catalogs",
        "bots",
        "migrations",
        "attachment-drafts",
        "acp-probe",
    ] {
        let candidates = existing_candidates(&roots, name)?;
        ensure!(candidates.len() <= 1, "conflicting v2 domain: {name}");
        if let Some(source) = candidates.first() {
            if name == "calls" {
                validate_family(&source.join("calls.sqlite"))?;
            }
            if name == "bots" {
                for bot in std::fs::read_dir(source)? {
                    let bot = bot?;
                    if bot.file_type()?.is_dir() {
                        validate_family(&bot.path().join("state.sqlite"))?;
                    }
                }
            }
        }
        let target = match name {
            "attachment-drafts" => stage.attachment_drafts_dir(),
            "acp-probe" => stage.acp_probe_root(),
            _ => stage.data_dir().join(name),
        };
        if journal.copied.contains(name) {
            continue;
        }
        if let Some(source) = candidates.first() {
            if name == "studio.sqlite" {
                for suffix in ["", "-wal", "-shm"] {
                    let member = sqlite_member(source, suffix);
                    if member.try_exists()? {
                        copy_tree(paths.home(), &member, &sqlite_member(&target, suffix)).await?;
                    }
                }
            } else {
                copy_tree(paths.home(), source, &target).await?;
            }
        } else if name == "studio.sqlite" {
            for root in &roots {
                ensure!(
                    !root.join("studio.sqlite-wal").try_exists()?
                        && !root.join("studio.sqlite-shm").try_exists()?,
                    "orphan v2 product database sidecars"
                );
            }
        }
        journal.copied.insert(name.into());
        persist(journal_path, journal).await?;
    }
    if has_v2 {
        let catalog = CatalogStore::load(stage.catalog_file()).await?;
        let workspaces = workspaces::WorkspaceStore::load(stage.workspaces_file()).await?;
        validate_directory(&catalog, &workspaces)?;
        let layout_root = existing_candidates(&roots, "projects")?;
        let flat_roots = existing_candidates(&roots, "sessions")?;
        ensure!(
            layout_root.len() <= 1 && flat_roots.len() <= 1,
            "ambiguous v2 session roots"
        );
        let legacy_journal = load_legacy_journal(&roots, &catalog, &workspaces).await?;
        let mut relocations = bot_roots::plan(paths, stage, &roots, &catalog).await?;
        if journal.copied.contains("bot-roots") {
            let mut original = journal.bot_roots.clone();
            for item in &mut original {
                item.blocked.clear();
            }
            ensure!(
                original == relocations,
                "bot root migration evidence changed"
            );
            for item in &mut relocations {
                if let Some(previous) = journal
                    .bot_roots
                    .iter()
                    .find(|previous| previous.bot_id == item.bot_id)
                {
                    item.blocked = previous.blocked.clone();
                }
            }
        }
        journal.bot_roots = relocations;
        journal.copied.insert("bot-roots".into());
        persist(journal_path, journal).await?;
        workspaces::relocate_managed_v2_paths(&stage.workspaces_file(), &journal.bot_roots).await?;
        for workspace in workspaces.entries() {
            let mut expected = WorkspaceManifest {
                schema_version: 2,
                workspace_id: workspace.id.clone(),
                kind: workspace.kind,
                path: workspace.path.clone(),
                ssh_alias: workspace.ssh_alias.clone(),
            };
            if let Some(root) = layout_root.first() {
                let manifest = root
                    .join(storage_key(&workspace.id, "Workspace")?)
                    .join("project.toml");
                if manifest.parent().context("manifest parent")?.try_exists()? {
                    let content = tokio::fs::read_to_string(&manifest)
                        .await
                        .context("grouped v2 Workspace manifest is missing")?;
                    let old = session_layout::schema::decode_v2_workspace(&manifest, &content)?;
                    ensure!(
                        old.workspace_id == workspace.id
                            && old.path == workspace.path
                            && old.ssh_alias == workspace.ssh_alias,
                        "v2 project manifest conflicts with canonical Workspace"
                    );
                }
            }
            if let Some(mapping) = journal.bot_roots.iter().find(|mapping| {
                mapping.workspace_id == workspace.id
                    && workspace.ssh_alias.is_none()
                    && workspace.path == mapping.old_root
                    && mapping
                        .threads
                        .values()
                        .any(|proof| proof.proven_local_root)
            }) {
                expected.path = mapping.new_root.clone();
            }
            session_layout::persist_workspace_manifest(stage, &expected).await?;
        }
        for mut entry in catalog.entries() {
            let key = storage_key(&entry.id, "Thread")?;
            let owner_key = storage_key(&entry.workspace_id, "Workspace")?;
            let grouped = layout_root
                .first()
                .map(|root| root.join(&owner_key).join("sessions").join(&key));
            let flat = flat_roots.first().map(|root| root.join(&key));
            let candidates = [grouped.as_ref(), flat.as_ref()]
                .into_iter()
                .flatten()
                .filter_map(|path| match path.try_exists() {
                    Ok(true) => Some(Ok(path.clone())),
                    Ok(false) => None,
                    Err(error) => Some(Err(error)),
                })
                .collect::<std::io::Result<Vec<_>>>()?;
            ensure!(
                candidates.len() <= 1,
                "both flat and grouped v2 session exist: {}",
                entry.id
            );
            if let Some(item) = legacy_journal.get(&entry.id) {
                ensure!(
                    !candidates.is_empty(),
                    "legacy layout journal source and target are both missing"
                );
                if item.phase != LegacyPhase::Planned {
                    ensure!(
                        candidates[0]
                            .components()
                            .any(|part| part.as_os_str() == "projects"),
                        "legacy layout journal says moved but only source exists"
                    );
                }
            }
            let original_manifest = SessionManifest::from_thread(&entry.to_thread());
            if let Some(mapping) = journal.bot_roots.iter().find(|mapping| {
                mapping
                    .threads
                    .get(&entry.id)
                    .is_some_and(|proof| proof.proven_local_root)
            }) {
                entry.workspace_path = mapping.new_root.clone();
            }
            let expected = SessionManifest::from_thread(&entry.to_thread());
            let target = stage.session_paths(&entry.workspace_id, &entry.id)?;
            if let Some(source) = candidates.first() {
                ensure_tree_safe(paths.home(), source).await?;
                let manifest_path = source.join("session.toml");
                if let Some(content) = optional_text(&manifest_path).await? {
                    ensure!(
                        session_layout::schema::decode_v2_session(&manifest_path, &content)?
                            == original_manifest,
                        "v2 session manifest conflicts with canonical catalog"
                    );
                } else {
                    ensure!(
                        Some(source) != grouped.as_ref(),
                        "grouped v2 session manifest is missing"
                    );
                }
                validate_family(&source.join("history.sqlite"))?;
                let label = format!("session:{}", entry.id);
                if !journal.copied.contains(&label) {
                    // Copy only owned files: opaque history and its WAL family are byte-preserved.
                    for name in [
                        "history.sqlite",
                        "history.sqlite-wal",
                        "history.sqlite-shm",
                        "state.toml",
                        "state.prev.toml",
                        "blobs/checkpoint",
                        "scratch",
                        "temp",
                    ] {
                        let from = source.join(name);
                        if from.try_exists()? {
                            let to = if name == "scratch" {
                                target.temp_dir()
                            } else {
                                target.root().join(name)
                            };
                            copy_tree(paths.home(), &from, &to).await?;
                        }
                    }
                    journal.copied.insert(label);
                    persist(journal_path, journal).await?;
                }
                let previous_flat = if legacy_journal.contains_key(&entry.id) {
                    flat.as_ref()
                        .map(|path| original_path(paths, path))
                        .transpose()?
                } else {
                    None
                };
                merge_resources(paths, source, previous_flat.as_deref(), &target).await?;
            }
            session_layout::persist_session_manifest(stage, &expected).await?;
        }
        crate::studio::catalog::relocate_managed_v2_paths(
            &stage.catalog_file(),
            &journal.bot_roots,
        )
        .await?;
    }
    Ok(())
}

fn existing_candidates(roots: &[PathBuf], name: &str) -> Result<Vec<PathBuf>> {
    let mut found = Vec::new();
    for root in roots {
        let path = root.join(name);
        if path.try_exists()? {
            found.push(path);
        }
    }
    Ok(found)
}
fn validate_directory(
    catalog: &CatalogStore,
    workspaces: &workspaces::WorkspaceStore,
) -> Result<()> {
    let entries = catalog.entries();
    let ids: BTreeMap<_, _> = entries
        .iter()
        .map(|entry| (entry.id.as_str(), entry))
        .collect();
    for entry in &entries {
        ensure!(
            workspaces.get(&entry.workspace_id).is_some(),
            "catalog owner is missing"
        );
        let mut seen = BTreeSet::new();
        let mut cursor = entry;
        loop {
            ensure!(seen.insert(&cursor.id), "catalog parent cycle");
            if let Some(parent) = &cursor.parent_thread_id {
                cursor = ids
                    .get(parent.as_str())
                    .context("catalog parent is missing")?;
                ensure!(
                    cursor.workspace_id == entry.workspace_id
                        && cursor.root_thread_id == entry.root_thread_id,
                    "catalog ownership mismatch"
                );
            } else {
                ensure!(cursor.id == entry.root_thread_id, "catalog root mismatch");
                break;
            }
        }
    }
    Ok(())
}

async fn merge_resources(
    paths: &StudioPaths,
    source: &Path,
    previous_flat: Option<&Path>,
    target: &crate::studio::paths::SessionPaths,
) -> Result<()> {
    let store = crate::resource_store::FileResourceStore::new(target.resources_dir());
    let tools = source.join("thread-resources");
    if tools.try_exists()? {
        let mut entries = tokio::fs::read_dir(&tools).await?;
        while let Some(entry) = entries.next_entry().await? {
            let name = entry
                .file_name()
                .into_string()
                .map_err(|_| anyhow::anyhow!("non UTF-8 resource identity"))?;
            ensure!(
                is_hash(&name) && entry.file_type().await?.is_file(),
                "invalid v2 reliable resource"
            );
            let reference = store
                .retain_file(&entry.path(), "application/octet-stream")
                .await?;
            ensure!(
                reference.content_digest() == format!("sha256:{name}"),
                "v2 tool resource digest mismatch"
            );
        }
    }
    let catalog_path = source.join("attachments.toml");
    if let Some(content) = optional_text(&catalog_path).await? {
        let mut catalog = attachment::decode_attachment_catalog(&catalog_path, &content)?;
        ensure!(
            catalog.thread_id == target.thread_id(),
            "attachment catalog belongs to another Thread"
        );
        let original_source = original_path(paths, source)?;
        let mut ids = BTreeSet::new();
        for record in &mut catalog.records {
            ensure!(
                record.thread_id == target.thread_id()
                    && ids.insert(record.id.clone())
                    && is_hash(&record.content_sha256),
                "invalid attachment identity"
            );
            let stored = Path::new(&record.blob_relative_path);
            let relative = if stored.is_absolute() {
                stored
                    .strip_prefix(&original_source)
                    .or_else(|error| {
                        previous_flat.map_or(Err(error), |flat| stored.strip_prefix(flat))
                    })
                    .context("absolute v2 attachment is outside its bound original session")?
            } else {
                stored
            };
            let canonical = crate::studio::paths::posix_relative(relative)?;
            ensure!(
                canonical.starts_with("blobs/") || canonical.starts_with("thread-resources/"),
                "v2 attachment escaped its resource root"
            );
            let from = source.join(&canonical);
            ensure_tree_safe(paths.home(), &from).await?;
            let reference = store.retain_file(&from, &record.media_type).await?;
            ensure!(
                reference.content_digest() == format!("sha256:{}", record.content_sha256)
                    && reference.byte_len() == record.byte_size,
                "v2 attachment integrity mismatch"
            );
            record.blob_relative_path = format!("resources/{}", record.content_sha256);
        }
        catalog.schema_version = attachment::ATTACHMENT_CATALOG_SCHEMA_VERSION;
        attachment::write_migrated_attachment_catalog(&target.attachments_catalog(), &catalog)
            .await?;
    }
    Ok(())
}
fn original_path(paths: &StudioPaths, source: &Path) -> Result<PathBuf> {
    let relative = source.strip_prefix(paths.home().join("migration-backups"))?;
    let mut components = relative.components();
    components.next().context("missing backup operation")?;
    Ok(paths.home().join(components.as_path()))
}
fn is_hash(name: &str) -> bool {
    name.len() == 64
        && name
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn validate_family(database: &Path) -> Result<()> {
    if !database.try_exists()? {
        for suffix in ["-wal", "-shm"] {
            let mut path = database.as_os_str().to_os_string();
            path.push(suffix);
            ensure!(!PathBuf::from(path).try_exists()?, "orphan SQLite sidecar");
        }
    }
    Ok(())
}

fn sqlite_member(database: &Path, suffix: &str) -> PathBuf {
    let mut path = database.as_os_str().to_os_string();
    path.push(suffix);
    PathBuf::from(path)
}

// Frozen original session-project-layout journal. It is consumed, never rewritten in the backup.
#[derive(Debug, Clone, Copy, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
enum LegacyPhase {
    Planned,
    Moved,
    Verified,
}
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LegacyMove {
    thread_id: String,
    project_id: String,
    source_key: String,
    target_project_key: String,
    target_thread_key: String,
    phase: LegacyPhase,
}
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LegacyJournal {
    schema_version: u32,
    completed: bool,
    orphans: Vec<String>,
    moves: Vec<LegacyMove>,
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LegacyMarker {
    schema_version: u32,
    completed: bool,
}
async fn load_legacy_journal(
    roots: &[PathBuf],
    catalog: &CatalogStore,
    workspaces: &workspaces::WorkspaceStore,
) -> Result<BTreeMap<String, LegacyMove>> {
    let records = existing_candidates(roots, "migrations/session-project-layout.toml")?;
    let markers = existing_candidates(roots, "migrations/session-project-layout.complete")?;
    ensure!(
        records.len() <= 1 && markers.len() <= 1 && (markers.is_empty() || !records.is_empty()),
        "ambiguous v2 layout journal"
    );
    let mut result = BTreeMap::new();
    if let Some(path) = records.first() {
        let record: LegacyJournal = toml::from_str(&tokio::fs::read_to_string(path).await?)?;
        ensure!(record.schema_version == 1, "future v2 layout journal");
        if let Some(path) = markers.first() {
            let marker: LegacyMarker = toml::from_str(&tokio::fs::read_to_string(path).await?)?;
            ensure!(
                marker.schema_version == 1 && marker.completed && record.completed,
                "inconsistent v2 layout completion"
            );
        }
        let _preserved_orphans = record.orphans;
        for item in record.moves {
            let entry = catalog
                .get(&item.thread_id)
                .context("v2 layout journal Thread is not registered")?;
            ensure!(
                entry.workspace_id == item.project_id
                    && workspaces.get(&item.project_id).is_some()
                    && item.source_key == storage_key(&item.thread_id, "Thread")?
                    && item.target_thread_key == item.source_key
                    && item.target_project_key == storage_key(&item.project_id, "Workspace")?,
                "v2 journal ownership mismatch"
            );
            ensure!(
                !record.completed || item.phase == LegacyPhase::Verified,
                "inconsistent v2 layout progress"
            );
            ensure!(
                result.insert(item.thread_id.clone(), item).is_none(),
                "duplicate v2 journal move"
            );
        }
    }
    Ok(result)
}

/// Copy without following links or overwriting a conflicting file; a previously copied exact file
/// proves an interrupted step. Unknown source entries remain only in the preserved root.
async fn copy_tree(home: &Path, source: &Path, target: &Path) -> Result<()> {
    let (home, source, target) = (home.to_owned(), source.to_owned(), target.to_owned());
    tokio::task::spawn_blocking(move || copy_tree_sync(&home, &source, &target)).await?
}
fn copy_tree_sync(home: &Path, source: &Path, target: &Path) -> Result<()> {
    pl_tool::workspace::path_safety::validate_path_for_write(home, target)?;
    let meta = std::fs::symlink_metadata(source)?;
    ensure!(
        !pl_tool::workspace::path_safety::is_link_or_reparse(&meta),
        "migration refuses links: {}",
        source.display()
    );
    if meta.is_dir() {
        std::fs::create_dir_all(target)?;
        for entry in std::fs::read_dir(source)? {
            let entry = entry?;
            copy_tree_sync(home, &entry.path(), &target.join(entry.file_name()))?;
        }
        #[cfg(unix)]
        std::fs::File::open(target)?.sync_all()?;
    } else {
        ensure!(meta.is_file(), "migration source is not a regular file");
        if target.try_exists()? {
            ensure!(
                file_digest(source)? == file_digest(target)?,
                "conflicting migration copy: {}",
                target.display()
            );
        } else {
            std::fs::create_dir_all(target.parent().context("copy target has no parent")?)?;
            let mut temporary = tempfile::NamedTempFile::new_in(
                target.parent().context("copy target has no parent")?,
            )?;
            std::io::copy(&mut std::fs::File::open(source)?, &mut temporary)?;
            temporary.as_file().sync_all()?;
            temporary.persist_noclobber(target)?;
            ensure!(
                file_digest(source)? == file_digest(target)?,
                "migration copy changed bytes"
            );
        }
        #[cfg(unix)]
        std::fs::File::open(target.parent().context("copy target parent")?)?.sync_all()?;
    }
    Ok(())
}
fn file_digest(path: &Path) -> Result<(u64, String)> {
    use std::io::Read;
    let mut file = std::fs::File::open(path)?;
    let mut hash = Sha256::new();
    let mut length = 0;
    let mut buffer = [0_u8; 65536];
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hash.update(&buffer[..count]);
        length += count as u64;
    }
    Ok((length, hex::encode(hash.finalize())))
}
async fn ensure_tree_safe(home: &Path, path: &Path) -> Result<()> {
    let (home, path) = (home.to_owned(), path.to_owned());
    tokio::task::spawn_blocking(move || {
        let mut pending = vec![path];
        while let Some(path) = pending.pop() {
            pl_tool::workspace::path_safety::validate_path_for_write(&home, &path)?;
            let meta = std::fs::symlink_metadata(&path)?;
            ensure!(
                !pl_tool::workspace::path_safety::is_link_or_reparse(&meta),
                "migration source contains a link"
            );
            if meta.is_dir() {
                for entry in std::fs::read_dir(path)? {
                    pending.push(entry?.path());
                }
            } else {
                ensure!(meta.is_file(), "migration source contains a non-file");
            }
        }
        Ok(())
    })
    .await?
}

#[cfg(test)]
mod tests;

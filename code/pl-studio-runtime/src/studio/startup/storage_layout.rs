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
const LAYOUT_SCHEMA_VERSION: u32 = 2;
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

enum SourceInstallation {
    Fresh,
    V2,
}

/// Created only after `build` verifies the preserved sources of an unpublished operation.
/// Its path binds the source classification to that operation's own staging database.
pub(in crate::studio) struct PreparedLayoutDatabase {
    path: PathBuf,
    source: SourceInstallation,
}

impl PreparedLayoutDatabase {
    pub(in crate::studio) fn path(&self) -> &Path {
        &self.path
    }

    pub(in crate::studio) fn has_v2_authority(&self) -> bool {
        matches!(self.source, SourceInstallation::V2)
    }
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
        let mut record = journal.as_deref().map(decode_journal).transpose()?;
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
            persist(&journal_path, record).await?;
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
        let database = build(paths, &stage, &backup, &journal_path, &mut journal).await?;
        // This is the production loader and official SeaORM schema sequence, not a second decoder.
        // Every raw family copy has completed before this may open or checkpoint SQLite.
        let store = StudioStore::prepare_layout_database(database).await?;
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
        // An older application may have stopped after preparing a v1 staging layout.
        upgrade_layout(paths, &stage, &marker, Some(&journal)).await?;
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

async fn build(
    paths: &StudioPaths,
    stage: &StudioPaths,
    backup: &Path,
    journal_path: &Path,
    journal: &mut Journal,
) -> Result<PreparedLayoutDatabase> {
    let roots = [backup.join("v2"), backup.join("studio/v2")];
    // Directory existence is not installation evidence: a cache-only v2 home never owned
    // canonical state. Conversely, any other material must not be adopted as a fresh install.
    let mut has_v2 = false;
    for root in &roots {
        if !root.try_exists()? {
            continue;
        }
        validate_family(&root.join("studio.sqlite"))?;
        validate_family(&root.join("calls/calls.sqlite"))?;
        for entry in std::fs::read_dir(root)? {
            let entry = entry?;
            let name = entry.file_name();
            let kind = entry.file_type()?;
            let independent = (kind.is_dir()
                && matches!(
                    name.to_str(),
                    Some(
                        "model-catalogs"
                            | "acp-probe"
                            | "attachment-drafts"
                            | "credential-transactions"
                    )
                ))
                || (kind.is_file()
                    && matches!(
                        name.to_str(),
                        Some("chatgpt-host.toml" | "chatgpt-host.lock")
                    ));
            if !independent {
                has_v2 = true;
            }
        }
    }
    if has_v2 {
        for name in ["studio.sqlite", "calls/calls.sqlite"] {
            ensure!(
                existing_candidates(&roots, name)?.len() == 1,
                "v2 authoritative {name} missing or duplicated"
            );
        }
    }
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
        "chatgpt-host.toml",
        "credential-transactions",
    ] {
        let candidates = existing_candidates(&roots, name)?;
        ensure!(candidates.len() <= 1, "conflicting v2 domain: {name}");
        if let Some(source) = candidates.first() {
            #[cfg(unix)]
            if name == "chatgpt-host.toml" {
                use std::os::unix::fs::PermissionsExt;
                ensure!(
                    std::fs::metadata(source)?.permissions().mode() & 0o077 == 0,
                    "ChatGPT host identity must be owner-only"
                );
            }
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
                match tokio::fs::read_to_string(&manifest).await {
                    Ok(content) => {
                        let old = session_layout::schema::decode_v2_workspace(&manifest, &content)?;
                        ensure!(
                            old.workspace_id == workspace.id
                                && old.path == workspace.path
                                && old.ssh_alias == workspace.ssh_alias,
                            "v2 project manifest conflicts with canonical Workspace"
                        );
                    }
                    // Workspaces owns identity; each registered session is verified below.
                    // A missing redundant project manifest must not prevent its migration.
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                    Err(error) => return Err(error.into()),
                }
            }
            if let Some(mapping) = journal.bot_roots.iter().find(|mapping| {
                mapping.workspace_id == workspace.id
                    && workspace.ssh_alias.is_none()
                    && bot_roots::same_path(
                        Path::new(&workspace.path),
                        Path::new(&mapping.old_root),
                    )
                    && mapping
                        .threads
                        .values()
                        .any(|proof| proof.proven_local_root)
            }) {
                expected.path = mapping.new_root.clone();
            }
            session_layout::persist_workspace_manifest(stage, &expected).await?;
        }
        for (mut session, agent) in catalog_directory_threads(&catalog) {
            let key = storage_key(&agent.thread_id, "Thread")?;
            let owner_key = storage_key(&session.workspace_id, "Workspace")?;
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
                candidates.len() == 1,
                "registered v2 session source missing or duplicated: {}",
                agent.thread_id
            );
            if let Some(item) = legacy_journal.get(&agent.thread_id)
                && item.phase != LegacyPhase::Planned
            {
                ensure!(
                    candidates[0]
                        .components()
                        .any(|part| part.as_os_str() == "projects"),
                    "legacy layout journal says moved but only source exists"
                );
            }
            let original_manifest =
                SessionManifest::from_directory_facts(&session, &agent, |id| {
                    catalog.get_agent(id)
                })?;
            if let Some(mapping) = journal.bot_roots.iter().find(|mapping| {
                mapping
                    .threads
                    .get(&agent.thread_id)
                    .is_some_and(|proof| proof.proven_local_root)
            }) {
                session.workspace_path = mapping.new_root.clone();
            }
            let expected = SessionManifest::from_directory_facts(&session, &agent, |id| {
                catalog.get_agent(id)
            })?;
            let target = stage.session_paths(&session.workspace_id, &agent.thread_id)?;
            {
                let source = &candidates[0];
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
                let label = format!("session:{}", agent.thread_id);
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
                let previous_flat = if legacy_journal.contains_key(&agent.thread_id) {
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
    // A fresh operation may resume its own partly-created target, but never adopt an orphan WAL.
    // Source families, copy hashes and ownership were checked above, independently of target state.
    validate_family(&stage.database())?;
    validate_family(&stage.calls_database())?;
    Ok(PreparedLayoutDatabase {
        path: stage.database(),
        source: if has_v2 {
            SourceInstallation::V2
        } else {
            SourceInstallation::Fresh
        },
    })
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
    let owned_sessions = catalog.sessions();
    let sessions: BTreeMap<_, _> = owned_sessions
        .iter()
        .map(|session| (session.session_id.as_str(), session))
        .collect();
    let agents = catalog.agents();
    let agent_ids: BTreeMap<_, _> = agents
        .iter()
        .map(|agent| (agent.agent_id.as_str(), agent))
        .collect();
    for session in sessions.values() {
        ensure!(
            workspaces.get(&session.workspace_id).is_some(),
            "catalog owner is missing"
        );
        ensure!(
            agent_ids.contains_key(session.root_agent_id.as_str()),
            "catalog session has no root member"
        );
    }
    for agent in &agents {
        let Some(session) = sessions.get(agent.session_id.as_str()) else {
            anyhow::bail!("catalog agent references a missing session");
        };
        let mut seen = BTreeSet::new();
        let mut cursor = agent;
        loop {
            ensure!(seen.insert(&cursor.agent_id), "catalog parent cycle");
            if let Some(parent) = &cursor.parent_agent_id {
                cursor = agent_ids
                    .get(parent.as_str())
                    .context("catalog parent is missing")?;
                ensure!(
                    cursor.session_id == agent.session_id,
                    "catalog ownership mismatch"
                );
            } else {
                ensure!(
                    cursor.agent_id == session.root_agent_id,
                    "catalog root mismatch"
                );
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
                .agent_by_thread(&item.thread_id)
                .and_then(|agent| {
                    catalog
                        .get_session(&agent.session_id)
                        .map(|session| (session, agent))
                })
                .map(|(session, _)| session)
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

/// 展开目录的会话×成员事实，供 v2 布局迁移逐 Thread 物理目录处理。
fn catalog_directory_threads(
    catalog: &CatalogStore,
) -> Vec<(
    crate::studio::records::SessionDirectoryRecord,
    crate::studio::records::AgentDirectoryRecord,
)> {
    let mut pairs = Vec::new();
    for session in catalog.sessions() {
        for agent in catalog.agents_for_session(&session.session_id) {
            pairs.push((session.clone(), agent));
        }
    }
    pairs
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
            let parent = target.parent().context("copy target has no parent")?;
            std::fs::create_dir_all(parent)?;
            // tempfile passes paths directly to Win32 when persisting, unlike std's file APIs.
            // Canonicalize the checked, existing parent so both paths use extended-length syntax
            // on Windows. Keep this native spelling local; storage identities remain unchanged.
            let parent = std::fs::canonicalize(parent)?;
            let destination =
                parent.join(target.file_name().context("copy target has no filename")?);
            let mut temporary = tempfile::NamedTempFile::new_in(&parent)?;
            std::io::copy(&mut std::fs::File::open(source)?, &mut temporary)?;
            temporary.as_file().sync_all()?;
            temporary.persist_noclobber(&destination)?;
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
mod tests {
    use super::*;
    use sea_orm::sqlx::{Connection, Executor};
    use sea_orm::{ConnectionTrait, DatabaseBackend, Statement};

    const OWNER: &str = "original-workspace";
    const THREAD: &str = "original-thread";
    const BODY: &[u8] = b"attachment and tool share exact bytes";

    #[tokio::test]
    async fn authentication_material_is_preserved_and_published_without_product_state() -> Result<()>
    {
        let home = tempfile::tempdir()?;
        let paths = StudioPaths::from_home(home.path().to_owned());
        let old = home.path().join("v2");
        tokio::fs::create_dir_all(old.join("credential-transactions/transaction")).await?;
        let identity = b"schema_version = 1\next_agent_host_id = 'urn:uuid:00000000-0000-4000-8000-000000000001'\n";
        tokio::fs::write(old.join("chatgpt-host.toml"), identity).await?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(
                old.join("chatgpt-host.toml"),
                std::fs::Permissions::from_mode(0o600),
            )?;
        }
        tokio::fs::write(
            old.join("credential-transactions/transaction/journal.json"),
            b"journal bytes",
        )
        .await?;
        prepare(&paths).await?;
        prepare(&paths).await?;
        assert_eq!(
            tokio::fs::read(paths.data_dir().join("chatgpt-host.toml")).await?,
            identity
        );
        assert_eq!(
            tokio::fs::read(
                paths
                    .data_dir()
                    .join("credential-transactions/transaction/journal.json")
            )
            .await?,
            b"journal bytes"
        );
        let record: Journal =
            toml::from_str(&tokio::fs::read_to_string(home.path().join(JOURNAL)).await?)?;
        let preserved = backup_root(&paths, &record).join("v2");
        assert_eq!(
            tokio::fs::read(preserved.join("chatgpt-host.toml")).await?,
            identity
        );
        assert_eq!(
            tokio::fs::read(preserved.join("credential-transactions/transaction/journal.json"))
                .await?,
            b"journal bytes"
        );
        Ok(())
    }

    async fn fixture(
        home: &Path,
        grouped: bool,
        standalone: bool,
    ) -> Result<(StudioPaths, PathBuf)> {
        let paths = StudioPaths::from_home(home.to_owned());
        let legacy = home.join("v2");
        tokio::fs::create_dir_all(&legacy).await?;
        let settings =
            crate::studio::store::settings::SettingsStore::load(legacy.join("settings.toml"))
                .await?;
        settings.persist_if_absent().await?;
        let kind = if standalone { "standalone" } else { "project" };
        tokio::fs::write(legacy.join("workspaces.toml"), format!("schemaVersion = 2\nrevision = 7\n[[workspaces]]\nid = '{OWNER}'\nkind = '{kind}'\nname = 'Owner'\npath = '/isolated-workspace'\ncreatedAt = 1\nupdatedAt = 2\nclosed = false\n")).await?;
        tokio::fs::write(legacy.join("catalog.toml"), format!("schemaVersion = 4\nrevision = 9\n[[entries]]\nid = '{THREAD}'\nprojectId = '{OWNER}'\ntitle = 'kept title'\nmode = 'mode.simple'\nworkspaceMode = 'local'\nworkspacePath = '/isolated-workspace'\nrootThreadId = '{THREAD}'\nrole = 'root'\nagentPath = '{THREAD}'\nstatus = 'idle'\ndelegationMode = 'profile'\ndelegationPreference = 'balanced'\nexplicitlyClosed = false\ncreatedAt = 1\nupdatedAt = 2\narchived = false\n")).await?;
        let key = storage_key(THREAD, "Thread")?;
        let session = if grouped {
            let root = legacy
                .join("projects")
                .join(storage_key(OWNER, "Workspace")?);
            tokio::fs::create_dir_all(&root).await?;
            tokio::fs::write(
                root.join("project.toml"),
                format!("schemaVersion = 1\nprojectId = '{OWNER}'\npath = '/isolated-workspace'\n"),
            )
            .await?;
            root.join("sessions").join(key)
        } else {
            legacy.join("sessions").join(key)
        };
        tokio::fs::create_dir_all(session.join("blobs/checkpoint")).await?;
        tokio::fs::create_dir_all(session.join("thread-resources")).await?;
        tokio::fs::create_dir_all(session.join("scratch/commands")).await?;
        tokio::fs::write(session.join("scratch/commands/capture"), b"temporary").await?;
        tokio::fs::write(
            session.join("blobs/checkpoint/saved"),
            b"opaque checkpoint body",
        )
        .await?;
        tokio::fs::write(session.join("session.toml"), format!("schemaVersion = 1\nthreadId = '{THREAD}'\nprojectId = '{OWNER}'\nrootThreadId = '{THREAD}'\nworkspaceMode = 'local'\nworkspacePath = '/isolated-workspace'\ncreatedAt = 1\n")).await?;
        let hash = hex::encode(Sha256::digest(BODY));
        let blob = session.join("blobs").join(&hash);
        tokio::fs::write(&blob, BODY).await?;
        tokio::fs::write(session.join("thread-resources").join(&hash), BODY).await?;
        let mut record = toml::Table::new();
        record.insert("id".into(), "kept-attachment-id".into());
        record.insert("threadId".into(), THREAD.into());
        record.insert("modality".into(), "file".into());
        record.insert("mediaType".into(), "text/plain".into());
        record.insert("filename".into(), "original.txt".into());
        record.insert(
            "storagePath".into(),
            blob.to_str().context("fixture path UTF8")?.into(),
        );
        record.insert("byteSize".into(), (BODY.len() as i64).into());
        record.insert("contentSha256".into(), hash.into());
        record.insert("createdAt".into(), 3.into());
        let catalog = toml::Table::from_iter([
            ("schemaVersion".into(), 1.into()),
            ("threadId".into(), THREAD.into()),
            ("records".into(), toml::Value::Array(vec![record.into()])),
        ]);
        tokio::fs::write(session.join("attachments.toml"), toml::to_string(&catalog)?).await?;
        tokio::fs::create_dir_all(legacy.join("bots/bot-test-one/workspace/.anywork/sessions"))
            .await?;
        tokio::fs::write(
        legacy.join("bots/bot-test-one/config.toml"),
        format!("schema_version=2\nid='bot-test-one'\nname='Preserved bot'\nproject_id='{OWNER}'\napp_id='cli_original'\nplatform='feishuChina'\nenabled=false\ntools_enabled=false\ntrusted_open_ids=[]\ntrusted_chat_ids=[]\nconfig_revision=9\ncreated_at=1\nupdated_at=2\n"),
    )
    .await?;
        tokio::fs::write(
            legacy.join("bots/bot-test-one/workspace/owned"),
            b"bot workspace bytes",
        )
        .await?;
        let calls =
            crate::studio::storage::calls::CallsStore::open(&legacy.join("calls/calls.sqlite"))
                .await?;
        calls.close().await?;
        // A canonical v2 installation owns both necessary database families.
        wal_family(&legacy.join("studio.sqlite"), true).await?;
        tokio::fs::write(
            legacy.join("calls/logs/preserved.txt"),
            b"original raw log bytes\0",
        )
        .await?;
        tokio::fs::create_dir_all(home.join("skills/private-user")).await?;
        tokio::fs::write(
            home.join("skills/private-user/SKILL.md"),
            b"private skill source",
        )
        .await?;
        tokio::fs::write(home.join("studio.sqlite"), b"pre-v2 product untouched").await?;
        tokio::fs::create_dir_all(home.join("v1")).await?;
        tokio::fs::write(home.join("v1/unknown"), b"pre-v2 unknown untouched").await?;
        Ok((paths, session))
    }

    #[tokio::test]
    async fn catalog_636_v2_stale_child_mode_migrates_through_runtime_and_reopens() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let (paths, _) = fixture(temp.path(), false, false).await?;
        let mut catalog: toml::Table = toml::from_str(include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tests/fixtures/migration-636/catalog-v4.toml"
        )))?;
        for entry in catalog["entries"]
            .as_array_mut()
            .context("synthetic entries")?
        {
            for field in ["id", "rootThreadId", "parentThreadId", "agentPath"] {
                if entry.get(field).and_then(toml::Value::as_str) == Some("cold") {
                    entry[field] = THREAD.into();
                }
            }
            entry["projectId"] = OWNER.into();
            entry["workspacePath"] = "/isolated-workspace".into();
        }
        let original_catalog = toml::to_string(&catalog)?;
        tokio::fs::write(temp.path().join("v2/catalog.toml"), &original_catalog).await?;
        let child = temp
            .path()
            .join("v2/sessions")
            .join(storage_key("synthetic-child", "Thread")?);
        tokio::fs::create_dir_all(&child).await?;
        let original_manifest = format!(
            "schemaVersion = 1\nthreadId = 'synthetic-child'\nprojectId = '{OWNER}'\nparentThreadId = '{THREAD}'\nrootThreadId = '{THREAD}'\nworkspaceMode = 'local'\nworkspacePath = '/isolated-workspace'\ncreatedAt = 2\n"
        );
        tokio::fs::write(child.join("session.toml"), &original_manifest).await?;
        let options = crate::StudioRuntimeOptions {
            studio_home: Some(temp.path().to_owned()),
            host: crate::StudioHostKind::Test,
            ..crate::StudioRuntimeOptions::desktop()
        };
        let runtime = crate::StudioRuntime::initialize(options.clone()).await?;
        assert!(runtime.runtime_snapshot().await?.startup_recovery.is_none());
        let root = runtime.read_thread(THREAD).await?;
        assert_eq!(root.workspace_id, OWNER);
        assert_eq!(root.mode, Some(pl_protocol::ThreadModeId::simple()));
        let child = runtime.read_thread("synthetic-child").await?;
        assert_eq!(child.root_thread_id, THREAD);
        assert_eq!(child.parent_thread_id.as_deref(), Some(THREAD));
        assert_eq!(child.workspace_id, OWNER);
        assert_eq!(
            child.frozen_model.context("frozen model")?.model_id,
            "synthetic-model"
        );
        runtime.shutdown_runtime().await?;
        for id in [THREAD, "synthetic-child"] {
            assert!(
                !paths.session_paths(OWNER, id)?.history_database().exists(),
                "catalog migration must not activate execution or create history"
            );
        }
        let journal = decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
        let preserved = backup_root(&paths, &journal).join("v2");
        assert_eq!(
            tokio::fs::read_to_string(preserved.join("catalog.toml")).await?,
            original_catalog
        );
        assert_eq!(
            tokio::fs::read_to_string(
                preserved
                    .join("sessions")
                    .join(storage_key("synthetic-child", "Thread")?)
                    .join("session.toml")
            )
            .await?,
            original_manifest
        );
        let upgraded = tokio::fs::read(paths.catalog_file()).await?;
        let reopened = crate::StudioRuntime::initialize(options).await?;
        assert!(
            reopened
                .runtime_snapshot()
                .await?
                .startup_recovery
                .is_none()
        );
        assert_eq!(
            reopened
                .read_thread("synthetic-child")
                .await?
                .root_thread_id,
            THREAD
        );
        reopened.shutdown_runtime().await?;
        assert_eq!(tokio::fs::read(paths.catalog_file()).await?, upgraded);
        assert!(!temp.path().join("startup-backups").exists());
        Ok(())
    }

    /// Snapshot a committed WAL family from a separate live donor. No connection ever opens the
    /// fixture family while the migration moves it.
    async fn wal_family(target: &Path, product: bool) -> Result<BTreeMap<String, Vec<u8>>> {
        let donor = tempfile::tempdir()?;
        let live = donor.path().join("donor.sqlite");
        let mut connection = sea_orm::sqlx::SqliteConnection::connect_with(
            &sea_orm::sqlx::sqlite::SqliteConnectOptions::new()
                .filename(&live)
                .create_if_missing(true),
        )
        .await?;
        connection
            .execute("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;")
            .await?;
        if product {
            connection
                .execute(include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/src/studio/store/product_schema.sql"
                )))
                .await?;
            connection
                .execute(include_str!(concat!(
                    env!("CARGO_MANIFEST_DIR"),
                    "/src/studio/store/agent_evaluations.sql"
                )))
                .await?;
            connection.execute("PRAGMA user_version=26;").await?;
        } else {
            connection.execute("CREATE TABLE retained (id TEXT PRIMARY KEY, body BLOB); INSERT INTO retained VALUES ('identity', x'006f7061717565');").await?;
        }
        if target
            .file_name()
            .is_some_and(|name| name == "state.sqlite")
        {
            connection.execute("CREATE TABLE bot_meta(id INTEGER PRIMARY KEY, schema_version INTEGER); INSERT INTO bot_meta VALUES(1,6); CREATE TABLE thread_bindings(thread_id TEXT, project_id TEXT, status TEXT);").await?;
        }
        let mut family = BTreeMap::new();
        tokio::fs::create_dir_all(target.parent().context("family parent")?).await?;
        for suffix in ["", "-wal", "-shm"] {
            let bytes = tokio::fs::read(format!("{}{suffix}", live.display())).await?;
            tokio::fs::write(format!("{}{suffix}", target.display()), &bytes).await?;
            family.insert(suffix.to_owned(), bytes);
        }
        connection.close().await?;
        Ok(family)
    }

    #[tokio::test]
    async fn grouped_and_flat_v2_preserve_sqlite_families_and_share_resources() -> Result<()> {
        for (grouped, standalone, missing_project_manifest) in [
            (true, false, false),
            (false, true, false),
            (true, false, true),
        ] {
            let temp = tempfile::tempdir()?;
            let (paths, old_session) = fixture(temp.path(), grouped, standalone).await?;
            let project_manifest = temp
                .path()
                .join("v2/projects")
                .join(storage_key(OWNER, "Workspace")?)
                .join("project.toml");
            if missing_project_manifest {
                tokio::fs::remove_file(&project_manifest).await?;
            }
            let family = wal_family(&old_session.join("history.sqlite"), false).await?;
            // Exercise split roots without duplicating the fixture's authoritative product family.
            for suffix in ["", "-wal", "-shm"] {
                tokio::fs::remove_file(temp.path().join(format!("v2/studio.sqlite{suffix}")))
                    .await?;
            }
            let product = wal_family(&temp.path().join("studio/v2/studio.sqlite"), true).await?;
            let bot = wal_family(
                &temp.path().join("v2/bots/bot-test-one/state.sqlite"),
                false,
            )
            .await?;
            prepare(&paths).await?;
            let journal =
                decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
            assert_eq!(journal.phase, Phase::Completed);
            let backup = backup_root(&paths, &journal);
            if missing_project_manifest {
                assert!(
                    !backup
                        .join(project_manifest.strip_prefix(temp.path())?)
                        .exists(),
                    "the original must not gain a synthesized manifest"
                );
            }
            let saved_session = backup.join(old_session.strip_prefix(temp.path())?);
            for (suffix, expected) in &family {
                assert_eq!(
                    tokio::fs::read(format!(
                        "{}{suffix}",
                        saved_session.join("history.sqlite").display()
                    ))
                    .await?,
                    *expected
                );
            }
            for (suffix, expected) in &product {
                assert_eq!(
                    tokio::fs::read(backup.join(format!("studio/v2/studio.sqlite{suffix}")))
                        .await?,
                    *expected
                );
            }
            for (suffix, expected) in &bot {
                assert!(
                    tokio::fs::read(
                        backup.join(format!("v2/bots/bot-test-one/state.sqlite{suffix}"))
                    )
                    .await?
                        == *expected,
                    "original bot family {suffix} was not preserved"
                );
                if suffix == "-shm" {
                    continue;
                } // SQLite owns mutable reader-coordination bytes.
                assert_eq!(
                    tokio::fs::read(
                        paths
                            .bot_dir("bot-test-one")
                            .join(format!("state.sqlite{suffix}"))
                    )
                    .await?,
                    *expected
                );
            }
            let session = paths.session_paths(OWNER, THREAD)?;
            assert_eq!(std::fs::read_dir(session.resources_dir())?.count(), 1);
            let hash = hex::encode(Sha256::digest(BODY));
            assert_eq!(
                tokio::fs::read(session.resources_dir().join(&hash)).await?,
                BODY
            );
            assert!(!session.root().join("blobs").join(&hash).exists());
            assert_eq!(
                tokio::fs::read(session.root().join("blobs/checkpoint/saved")).await?,
                b"opaque checkpoint body"
            );
            assert_eq!(
                tokio::fs::read(session.temp_dir().join("commands/capture")).await?,
                b"temporary"
            );
            assert_eq!(
                tokio::fs::read(paths.calls_dir().join("logs/preserved.txt")).await?,
                b"original raw log bytes\0"
            );
            assert!(backup.join("skills/private-user/SKILL.md").exists());
            assert!(!temp.path().join("skills").exists());
            let manifest: WorkspaceManifest = toml::from_str(
                &tokio::fs::read_to_string(paths.workspace_manifest(OWNER)?).await?,
            )?;
            assert_eq!(
                manifest.kind == pl_protocol::studio::WorkspaceKind::Standalone,
                standalone
            );
            let store = StudioStore::prepare_database(&paths.database()).await?;
            let attachments = store.list_thread_attachments(THREAD).await?;
            assert_eq!(attachments[0].id, "kept-attachment-id");
            assert_eq!(
                attachments[0].blob_relative_path,
                format!("resources/{hash}")
            );
            assert_eq!(
                store
                    .read_attachment_bytes(THREAD, "kept-attachment-id")
                    .await?,
                BODY
            );
            assert_eq!(
                store
                    .catalog()
                    .get_session(THREAD)
                    .context("retained catalog")?
                    .last_user_message_at,
                None
            );
            for name in ["projects", "threads", "app_settings"] {
                assert!(
                    store
                        .database()
                        .query_one_raw(Statement::from_sql_and_values(
                            DatabaseBackend::Sqlite,
                            "SELECT name FROM sqlite_schema WHERE name=?",
                            [name.into()]
                        ))
                        .await?
                        .is_none()
                );
            }
            store.close().await?;
            // Successful startup does not rescan a later invalid source or reset isolated old versions.
            tokio::fs::create_dir_all(temp.path().join("v2")).await?;
            tokio::fs::write(temp.path().join("v2/unowned"), b"not claimed").await?;
            prepare(&paths).await?;
            assert_eq!(
                tokio::fs::read(temp.path().join("studio.sqlite")).await?,
                b"pre-v2 product untouched"
            );
            assert_eq!(
                tokio::fs::read(temp.path().join("v1/unknown")).await?,
                b"pre-v2 unknown untouched"
            );
        }
        Ok(())
    }

    #[tokio::test]
    async fn interrupted_move_copy_and_publication_resume_without_reclaiming_targets() -> Result<()>
    {
        let temp = tempfile::tempdir()?;
        let (paths, _) = fixture(temp.path(), false, false).await?;
        let mut journal = Journal {
            schema_version: 1,
            operation_id: "layout-interrupted-operation".into(),
            phase: Phase::Preserving,
            roots: ROOTS
                .into_iter()
                .map(|source| RootMove {
                    source: source.into(),
                    present: temp.path().join(source).exists(),
                    moved: false,
                })
                .collect(),
            copied: BTreeSet::new(),
            bot_roots: Vec::new(),
        };
        persist(&temp.path().join(JOURNAL), &journal).await?;
        managed_move(
            &temp.path().join("v2"),
            &backup_root(&paths, &journal).join("v2"),
        )
        .await?;
        // rename succeeded, journal update did not.
        prepare(&paths).await?;
        journal = decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
        assert_eq!(journal.phase, Phase::Completed);
        journal.phase = Phase::Publishing;
        persist(&temp.path().join(JOURNAL), &journal).await?;
        // publishing directory move succeeded, journal update did not.
        prepare(&paths).await?;
        assert_eq!(
            decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?.phase,
            Phase::Completed
        );
        Ok(())
    }

    #[tokio::test]
    async fn legacy_mid_move_journal_accepts_only_proven_grouped_destination() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let (paths, flat) = fixture(temp.path(), false, false).await?;
        let owner_key = storage_key(OWNER, "Workspace")?;
        let thread_key = storage_key(THREAD, "Thread")?;
        let grouped = temp
            .path()
            .join("v2/projects")
            .join(&owner_key)
            .join("sessions")
            .join(&thread_key);
        tokio::fs::create_dir_all(grouped.parent().context("parent")?).await?;
        tokio::fs::write(
            grouped
                .parent()
                .context("sessions")?
                .parent()
                .context("owner")?
                .join("project.toml"),
            format!("schemaVersion=1\nprojectId='{OWNER}'\npath='/isolated-workspace'\n"),
        )
        .await?;
        tokio::fs::rename(&flat, &grouped).await?;
        tokio::fs::create_dir_all(temp.path().join("v2/migrations")).await?;
        tokio::fs::write(temp.path().join("v2/migrations/session-project-layout.toml"), format!("schemaVersion=1\ncompleted=false\norphans=[]\n[[moves]]\nthreadId='{THREAD}'\nprojectId='{OWNER}'\nsourceKey='{thread_key}'\ntargetProjectKey='{owner_key}'\ntargetThreadKey='{thread_key}'\nphase='planned'\n")).await?;
        prepare(&paths).await?;
        assert!(
            paths
                .session_paths(OWNER, THREAD)?
                .attachments_catalog()
                .exists()
        );
        Ok(())
    }

    #[tokio::test]
    async fn invalid_inputs_keep_originals_and_never_publish_default_layout() -> Result<()> {
        for fault in [
            "future-catalog",
            "missing-catalog",
            "missing-attachment",
            "resource-digest",
            "bad-journal",
            "conflicting-target",
            "orphan-wal",
            "conflicting-project-manifest",
        ] {
            let temp = tempfile::tempdir()?;
            let (paths, session) =
                fixture(temp.path(), fault == "conflicting-project-manifest", false).await?;
            let hash = hex::encode(Sha256::digest(BODY));
            match fault {
                "future-catalog" => {
                    let path = temp.path().join("v2/catalog.toml");
                    let content = tokio::fs::read_to_string(&path)
                        .await?
                        .replace("schemaVersion = 4", "schemaVersion = 99");
                    tokio::fs::write(path, content).await?;
                }
                "missing-catalog" => {
                    tokio::fs::remove_file(temp.path().join("v2/catalog.toml")).await?
                }
                "missing-attachment" => {
                    tokio::fs::remove_file(session.join("blobs").join(&hash)).await?
                }
                "resource-digest" => {
                    tokio::fs::write(session.join("thread-resources").join(&hash), b"corrupt")
                        .await?
                }
                "bad-journal" => tokio::fs::write(temp.path().join(JOURNAL), b"bad = [").await?,
                "conflicting-target" => {
                    tokio::fs::create_dir_all(paths.data_dir()).await?;
                    tokio::fs::write(paths.data_dir().join("unknown"), b"untouched").await?;
                }
                "orphan-wal" => {
                    tokio::fs::write(session.join("history.sqlite-wal"), b"orphan").await?
                }
                "conflicting-project-manifest" => {
                    let path = temp
                        .path()
                        .join("v2/projects")
                        .join(storage_key(OWNER, "Workspace")?)
                        .join("project.toml");
                    tokio::fs::write(
                        path,
                        "schemaVersion=1\nprojectId='unrelated'\npath='/other'\n",
                    )
                    .await?;
                }
                _ => unreachable!(),
            }
            for _ in 0..2 {
                let error = prepare(&paths).await.expect_err(fault);
                assert!(
                    error
                        .chain()
                        .any(|cause| cause.is::<SessionLayoutMigrationFailed>())
                );
                assert!(!paths.layout_file().exists(), "{fault}");
            }
            // Source bytes either remain in place or in the operation-bound backup, never reset.
            assert_eq!(
                tokio::fs::read(temp.path().join("studio.sqlite")).await?,
                b"pre-v2 product untouched"
            );
            if fault == "conflicting-target" {
                assert_eq!(
                    tokio::fs::read(paths.data_dir().join("unknown")).await?,
                    b"untouched"
                );
            } else if fault != "bad-journal" {
                let journal =
                    decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
                assert!(
                    backup_root(&paths, &journal)
                        .join("v2/workspaces.toml")
                        .exists()
                );
            }
        }
        Ok(())
    }

    #[tokio::test]
    async fn registered_v2_sessions_without_sources_fail_on_every_restart() -> Result<()> {
        for grouped in [false, true] {
            let temp = tempfile::tempdir()?;
            let (paths, source) = fixture(temp.path(), grouped, !grouped).await?;
            let catalog = tokio::fs::read(temp.path().join("v2/catalog.toml")).await?;
            tokio::fs::remove_dir_all(source).await?;
            for _ in 0..2 {
                let error = prepare(&paths)
                    .await
                    .expect_err("missing registered session");
                assert!(format!("{error:#}").contains("registered v2 session source missing"));
                assert!(!paths.data_dir().exists());
                let journal =
                    decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
                assert_eq!(journal.phase, Phase::Building);
                assert_eq!(
                    tokio::fs::read(backup_root(&paths, &journal).join("v2/catalog.toml")).await?,
                    catalog
                );
                let stage = staging(&paths, &journal);
                assert!(!stage.layout_file().exists());
                assert!(
                    !stage
                        .session_paths(OWNER, THREAD)?
                        .root()
                        .join("session.toml")
                        .exists()
                );
            }
        }
        Ok(())
    }

    #[tokio::test]
    async fn canonical_v2_missing_database_families_never_create_replacements() -> Result<()> {
        for name in ["studio.sqlite", "calls/calls.sqlite"] {
            let temp = tempfile::tempdir()?;
            let (paths, _) = fixture(temp.path(), true, false).await?;
            let catalog = tokio::fs::read(temp.path().join("v2/catalog.toml")).await?;
            for suffix in ["", "-wal", "-shm"] {
                let member = temp.path().join(format!("v2/{name}{suffix}"));
                if member.exists() {
                    tokio::fs::remove_file(member).await?;
                }
            }
            for _ in 0..2 {
                let error = prepare(&paths).await.expect_err(name);
                assert!(
                    format!("{error:#}").contains(&format!("v2 authoritative {name} missing")),
                    "{error:#}"
                );
                assert!(!paths.data_dir().exists());
                let journal =
                    decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
                let stage = staging(&paths, &journal);
                assert!(!stage.data_dir().join(name).exists());
                assert!(!stage.layout_file().exists());
                let backup = backup_root(&paths, &journal);
                assert_eq!(
                    tokio::fs::read(backup.join("v2/catalog.toml")).await?,
                    catalog
                );
                assert!(backup.join("v2/calls/logs/preserved.txt").exists());
            }
        }
        Ok(())
    }

    #[tokio::test]
    async fn orphan_database_sidecars_in_other_v2_root_are_not_ignored() -> Result<()> {
        for name in ["studio.sqlite", "calls/calls.sqlite"] {
            let temp = tempfile::tempdir()?;
            let (paths, _) = fixture(temp.path(), false, false).await?;
            let sidecar = temp.path().join(format!("studio/v2/{name}-wal"));
            tokio::fs::create_dir_all(sidecar.parent().context("sidecar parent")?).await?;
            tokio::fs::write(&sidecar, b"orphan database bytes").await?;
            for _ in 0..2 {
                prepare(&paths).await.expect_err(name);
                assert!(!paths.layout_file().exists());
            }
            let journal =
                decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
            assert_eq!(
                tokio::fs::read(
                    backup_root(&paths, &journal).join(sidecar.strip_prefix(temp.path())?)
                )
                .await?,
                b"orphan database bytes"
            );
        }
        Ok(())
    }

    #[tokio::test]
    async fn fresh_and_cache_only_v2_homes_create_complete_current_installations() -> Result<()> {
        for cache_only in [false, true] {
            let temp = tempfile::tempdir()?;
            let paths = StudioPaths::from_home(temp.path().to_owned());
            if cache_only {
                tokio::fs::create_dir_all(temp.path().join("v2/model-catalogs")).await?;
                tokio::fs::write(
                    temp.path().join("v2/model-catalogs/cache"),
                    b"rebuildable catalog bytes",
                )
                .await?;
            }
            prepare(&paths).await?;
            prepare(&paths).await?;
            let store = StudioStore::prepare_database(&paths.database()).await?;
            assert!(store.catalog().sessions().is_empty());
            assert!(store.catalog().agents().is_empty());
            assert!(paths.calls_database().exists());
            assert!(paths.database().exists());
            assert!(paths.layout_file().exists());
            store.close().await?;
            if cache_only {
                assert_eq!(
                    tokio::fs::read(paths.model_catalogs_dir().join("cache")).await?,
                    b"rebuildable catalog bytes"
                );
            }
        }
        Ok(())
    }

    #[tokio::test]
    async fn building_fresh_staging_resumes_product_and_documents_before_calls() -> Result<()> {
        for cache_only in [false, true] {
            let temp = tempfile::tempdir()?;
            let paths = StudioPaths::from_home(temp.path().to_owned());
            if cache_only {
                tokio::fs::create_dir_all(temp.path().join("v2/model-catalogs")).await?;
                tokio::fs::write(
                    temp.path().join("v2/model-catalogs/cache"),
                    b"retained cache",
                )
                .await?;
            }
            let mut journal = Journal {
                schema_version: 1,
                operation_id: "layout-interrupted-fresh".into(),
                phase: Phase::Building,
                roots: ROOTS
                    .into_iter()
                    .map(|source| {
                        let present = temp.path().join(source).exists();
                        RootMove {
                            source: source.into(),
                            present,
                            moved: present,
                        }
                    })
                    .collect(),
                copied: BTreeSet::new(),
                bot_roots: Vec::new(),
            };
            let backup = backup_root(&paths, &journal);
            for root in &journal.roots {
                if root.present {
                    managed_move(&temp.path().join(&root.source), &backup.join(&root.source))
                        .await?;
                }
            }
            let journal_path = temp.path().join(JOURNAL);
            persist(&journal_path, &journal).await?;
            let stage = staging(&paths, &journal);
            tokio::fs::create_dir_all(stage.data_dir()).await?;
            let _ = build(&paths, &stage, &backup, &journal_path, &mut journal).await?;

            // Synthesize the precise interrupted phase from a closed production donor: product and
            // all canonical TOML exist, calls has never been created. This is not crash injection.
            let donor_home = tempfile::tempdir()?;
            let donor = StudioPaths::from_home(donor_home.path().to_owned());
            let store = StudioStore::prepare_database(&donor.database()).await?;
            let payload = r#"{"retained":"staging-owned"}"#;
            store.database().execute_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "INSERT INTO studio_objects VALUES ('thread','stage-owner','resumeProbe',7,1,?,?,42)",
            vec![payload.into(), pl_core::context::content_hash(payload.as_bytes()).into()],
        )).await?;
            store.close().await?;
            for name in [
                "studio.sqlite",
                "studio.sqlite-wal",
                "studio.sqlite-shm",
                "settings.toml",
                "catalog.toml",
                "workspaces.toml",
            ] {
                let source = donor.data_dir().join(name);
                if source.exists() {
                    copy_tree(paths.home(), &source, &stage.data_dir().join(name)).await?;
                }
            }
            assert!(!stage.calls_database().exists());
            assert!(!stage.layout_file().exists());
            // The same files without the operation's capability still fail the normal Existing gate.
            let error = StudioStore::prepare_database(&stage.database())
                .await
                .err()
                .context("normal prepare must not treat a missing calls DB as fresh")?;
            assert!(format!("{error:#}").contains("calls/calls.sqlite is missing"));

            for _ in 0..2 {
                let runtime = crate::StudioRuntime::initialize(crate::StudioRuntimeOptions {
                    studio_home: Some(temp.path().to_owned()),
                    host: crate::StudioHostKind::Test,
                    ..crate::StudioRuntimeOptions::desktop()
                })
                .await?;
                runtime.shutdown_runtime().await?;
                assert!(paths.database().exists());
                assert!(paths.calls_database().exists());
                let saved = decode_journal(&tokio::fs::read_to_string(&journal_path).await?)?;
                assert_eq!(saved.operation_id, journal.operation_id);
                assert_eq!(saved.phase, Phase::Completed);
                assert!(!stage.data_dir().exists());
            }
            let mut database = sea_orm::sqlx::SqliteConnection::connect_with(
                &sea_orm::sqlx::sqlite::SqliteConnectOptions::new()
                    .filename(paths.database())
                    .read_only(true),
            )
            .await?;
            let retained: (i64, String) = sea_orm::sqlx::query_as(
                "SELECT revision,payload_json FROM studio_objects WHERE object_kind='resumeProbe'",
            )
            .fetch_one(&mut database)
            .await?;
            assert_eq!(retained, (7, payload.into()));
            database.close().await?;
            if cache_only {
                assert_eq!(
                    tokio::fs::read(backup.join("v2/model-catalogs/cache")).await?,
                    b"retained cache"
                );
                assert_eq!(
                    tokio::fs::read(paths.model_catalogs_dir().join("cache")).await?,
                    b"retained cache"
                );
            }
        }
        Ok(())
    }

    #[tokio::test]
    async fn unknown_v2_material_is_not_a_fresh_installation() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::from_home(temp.path().to_owned());
        tokio::fs::create_dir_all(temp.path().join("v2")).await?;
        tokio::fs::write(temp.path().join("v2/unknown"), b"unclassified state").await?;
        for _ in 0..2 {
            prepare(&paths)
                .await
                .expect_err("unknown installation evidence");
            assert!(!paths.data_dir().exists());
        }
        let journal = decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
        assert_eq!(
            tokio::fs::read(backup_root(&paths, &journal).join("v2/unknown")).await?,
            b"unclassified state"
        );
        Ok(())
    }

    #[tokio::test]
    async fn failed_shared_attachment_batch_keeps_tool_and_prior_attachment_resources() -> Result<()>
    {
        let temp = tempfile::tempdir()?;
        let (paths, _) = fixture(temp.path(), false, false).await?;
        prepare(&paths).await?;
        let store = StudioStore::prepare_database(&paths.database()).await?;
        let session = paths.session_paths(OWNER, THREAD)?;
        let hash = hex::encode(Sha256::digest(BODY));
        let draft = attachment::AttachmentDraftObject {
            draft_id: "new-draft".into(),
            modality: pl_protocol::studio::StudioAttachmentModality::File,
            media_type: "text/plain".into(),
            filename: "same.txt".into(),
            storage_path: session.resources_dir().join(&hash),
            byte_size: BODY.len() as u64,
            content_sha256: hash.clone(),
            width: None,
            height: None,
            initial_remote_url: None,
        };
        let mut missing = draft.clone();
        missing.storage_path = temp.path().join("not-created");
        assert!(
            store
                .promote_attachment_drafts(THREAD, &[draft.clone(), missing])
                .await
                .is_err()
        );
        assert_eq!(
            store
                .read_attachment_bytes(THREAD, "kept-attachment-id")
                .await?,
            BODY
        );
        assert_eq!(std::fs::read_dir(session.resources_dir())?.count(), 1);
        let promoted = store.promote_attachment_drafts(THREAD, &[draft]).await?;
        assert_eq!(promoted[0].blob_relative_path, format!("resources/{hash}"));
        assert_eq!(std::fs::read_dir(session.resources_dir())?.count(), 1);
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn interrupted_build_resumes_verified_copies_and_current_missing_authority_is_not_reset()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let (paths, session) = fixture(temp.path(), false, false).await?;
        let hash = hex::encode(Sha256::digest(BODY));
        tokio::fs::remove_file(session.join("blobs").join(&hash)).await?;
        assert!(prepare(&paths).await.is_err());
        let journal = decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
        assert_eq!(journal.phase, Phase::Building);
        let original = backup_root(&paths, &journal).join(session.strip_prefix(temp.path())?);
        let checkpoint = staging(&paths, &journal)
            .session_paths(OWNER, THREAD)?
            .root()
            .join("blobs/checkpoint/saved");
        #[cfg(windows)]
        {
            use std::os::windows::ffi::OsStrExt;
            assert!(checkpoint.as_os_str().encode_wide().count() > 260);
        }
        // The missing attachment interrupts the build only after deep owned copies are published.
        // Reuse requires identical bytes, and a conflicting copy must never reclaim that target.
        let saved = tokio::fs::read(original.join("blobs/checkpoint/saved")).await?;
        assert_eq!(tokio::fs::read(&checkpoint).await?, saved);
        copy_tree(
            paths.home(),
            &original.join("blobs/checkpoint/saved"),
            &checkpoint,
        )
        .await?;
        let error = copy_tree(
            paths.home(),
            &original.join("attachments.toml"),
            &checkpoint,
        )
        .await
        .expect_err("conflicting copy must preserve the already published checkpoint");
        assert!(format!("{error:#}").contains("conflicting migration copy"));
        assert_eq!(tokio::fs::read(&checkpoint).await?, saved);
        assert!(!paths.layout_file().exists());
        tokio::fs::write(original.join("blobs").join(&hash), BODY).await?;
        prepare(&paths).await?;
        let marker = tokio::fs::read(paths.layout_file()).await?;
        tokio::fs::remove_file(paths.catalog_file()).await?;
        for _ in 0..2 {
            assert!(prepare(&paths).await.is_err());
        }
        assert!(!paths.catalog_file().exists());
        assert_eq!(tokio::fs::read(paths.layout_file()).await?, marker);
        assert!(original.join("attachments.toml").exists());
        Ok(())
    }

    #[tokio::test]
    async fn future_layout_and_storage_journal_versions_are_not_new_installations() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::from_home(temp.path().to_owned());
        for content in [
            "schemaVersion=99\noperationId='layout-future'\n",
            "schemaVersion=1\noperationId='../escape'\n",
        ] {
            tokio::fs::create_dir_all(paths.data_dir()).await?;
            tokio::fs::write(paths.layout_file(), content).await?;
            assert!(prepare(&paths).await.is_err());
            assert_eq!(
                tokio::fs::read_to_string(paths.layout_file()).await?,
                content
            );
        }
        assert!(
        decode_journal(
            "schemaVersion=99\noperationId='layout-future'\nphase='building'\nroots=[]\ncopied=[]\n"
        )
        .is_err()
    );
        Ok(())
    }

    fn bot_checkpoint(
        thread_id: &str,
        bot: &str,
        root: &str,
        child: bool,
    ) -> Result<pl_core::thread::ThreadCheckpoint> {
        use pl_core::{
            context::OpaquePayload,
            thread::{ThreadCheckpoint, ThreadSnapshot, extensions::ExtensionRecord},
        };
        let mut extensions = BTreeMap::from([
            (
                "studio.bot-owner".into(),
                ExtensionRecord {
                    revision: 3,
                    payload: crate::studio::model_route::encode_bot_owner(bot)?,
                },
            ),
            (
                "studio.project".into(),
                ExtensionRecord {
                    revision: 5,
                    payload: OpaquePayload::new(
                        "pl.studio.project",
                        1,
                        serde_json::to_string(&crate::studio::WorkspaceRecord {
                            id: OWNER.into(),
                            kind: pl_protocol::studio::WorkspaceKind::Project,
                            name: "Frozen effective owner".into(),
                            path: root.into(),
                            ssh_alias: None,
                            updated_at: 7,
                        })?,
                    )?,
                },
            ),
            (
                "unrelated.opaque".into(),
                ExtensionRecord {
                    revision: 2,
                    payload: OpaquePayload::new(
                        "fixture.opaque",
                        1,
                        format!("original path string: {root}"),
                    )?,
                },
            ),
        ]);
        if child {
            extensions.insert(
                "studio.workspace".into(),
                ExtensionRecord {
                    revision: 9,
                    payload: crate::studio::workspace_receipt::to_payload(
                        &pl_protocol::AgentWorkspaceAssignmentSnapshot {
                            mode: pl_protocol::AgentWorkspaceMode::Directory,
                            project_root: root.into(),
                            root: root.into(),
                            writable_paths: Some(Vec::new()),
                            worktree: None,
                            review_target: None,
                        },
                    )?,
                },
            );
        }
        Ok(ThreadCheckpoint::capture(
            thread_id.into(),
            0,
            ThreadSnapshot {
                extensions,
                extension_sequence: 9,
                ..Default::default()
            },
        )?)
    }

    async fn checkpoint_family(
        target: &Path,
        checkpoint: &pl_core::thread::ThreadCheckpoint,
    ) -> Result<()> {
        let donor = tempfile::tempdir()?;
        let live = donor.path().join("history.sqlite");
        let history =
            crate::studio::storage::history::HistoryStore::open(&live, &checkpoint.thread_id)
                .await?;
        history.import_checkpoint(checkpoint, &[]).await?;
        // The donor is not a migration source. Snapshot its quiescent committed family; no
        // connection ever targets the independently copied fixture while layout migration moves it.
        for suffix in ["", "-wal", "-shm"] {
            let source = donor.path().join(format!("history.sqlite{suffix}"));
            if source.exists() {
                tokio::fs::copy(
                    source,
                    target.with_file_name(format!("history.sqlite{suffix}")),
                )
                .await?;
            }
        }
        Ok(())
    }

    async fn prepared_history_family(target: &Path, thread: &str, fence: u64) -> Result<()> {
        let donor = tempfile::tempdir()?;
        let live = donor.path().join("history.sqlite");
        let history = crate::studio::storage::history::HistoryStore::open(&live, thread).await?;
        // The real history owner initializes its schema and commits facts, but no checkpoint import
        // has happened yet. Capture only a quiescent donor, never open the migration fixture in flight.
        crate::studio::storage::history::persist_completed(&history, fence, &[]).await?;
        assert!(history.checkpoint().await?.is_none());
        for suffix in ["", "-wal", "-shm"] {
            let from = donor.path().join(format!("history.sqlite{suffix}"));
            if from.exists() {
                tokio::fs::copy(
                    from,
                    target.with_file_name(format!("history.sqlite{suffix}")),
                )
                .await?;
            }
        }
        Ok(())
    }

    #[cfg(windows)]
    #[test]
    fn bot_root_relocation_accepts_only_safe_windows_path_spellings() -> Result<()> {
        let mapping = bot_roots::BotRootMove {
            bot_id: "bot-test-one".into(),
            workspace_id: OWNER.into(),
            old_root: r"C:\anywork\v2\bots\bot-test-one\workspace".into(),
            new_root: r"C:\anywork\data\bots\bot-test-one\workspace".into(),
            threads: BTreeMap::new(),
            blocked: BTreeMap::new(),
        };
        // These persisted addresses need no live source directory after publication.
        for root in [&mapping.old_root, &mapping.new_root] {
            for mut value in [root.clone(), format!(r"\\?\{root}")] {
                mapping.exact_path(&mut value)?;
                assert_eq!(value, mapping.new_root);
                mapping.exact_path(&mut value)?;
                assert_eq!(value, mapping.new_root);
            }
        }
        for original in [
            format!(r"{}\child", mapping.old_root),
            format!("{}-other", mapping.old_root),
            format!(r"\\?\{}.", mapping.old_root),
            format!(r"\\?\{} ", mapping.old_root),
            format!(r"\\?\{}\..\workspace", mapping.old_root),
            r"C:\anywork\v2\bots\bot-other\workspace".into(),
        ] {
            let mut value = original.clone();
            assert!(mapping.exact_path(&mut value).is_err(), "{original}");
            assert_eq!(value, original, "rejected execution addresses stay intact");
        }
        Ok(())
    }

    async fn bot_binding_fixture(home: &Path, frozen_bot: &str) -> Result<(StudioPaths, String)> {
        // Keep the migration home in the application's spelling, while old execution
        // bindings may retain std::fs::canonicalize's Windows verbatim prefix.
        let home = dunce::canonicalize(home)?;
        let home = home.as_path();
        let (paths, session) = fixture(home, true, false).await?;
        let old_root = dunce::canonicalize(home.join("v2/bots/bot-test-one/workspace"))?
            .to_str()
            .context("old root")?
            .to_owned();
        let frozen_root = std::fs::canonicalize(&old_root)?
            .to_str()
            .context("frozen root")?
            .to_owned();
        let catalog_path = home.join("v2/catalog.toml");
        let mut catalog: toml::Table =
            toml::from_str(&tokio::fs::read_to_string(&catalog_path).await?)?;
        let entries = catalog
            .get_mut("entries")
            .and_then(toml::Value::as_array_mut)
            .context("entries")?;
        entries[0]["workspacePath"] = frozen_root.clone().into();
        let mut child = entries[0].clone();
        child["id"] = "bot-child".into();
        child["agentPath"] = "bot-child".into();
        child["role"] = "child".into();
        child
            .as_table_mut()
            .context("child entry")?
            .insert("parentThreadId".into(), THREAD.into());
        entries.push(child);
        tokio::fs::write(catalog_path, toml::to_string(&catalog)?).await?;
        let manifest_path = session.join("session.toml");
        let mut manifest: toml::Table =
            toml::from_str(&tokio::fs::read_to_string(&manifest_path).await?)?;
        manifest["workspacePath"] = frozen_root.clone().into();
        tokio::fs::write(manifest_path, toml::to_string(&manifest)?).await?;
        checkpoint_family(
            &session.join("history.sqlite"),
            &bot_checkpoint(THREAD, frozen_bot, &frozen_root, false)?,
        )
        .await?;
        let child_session = session
            .parent()
            .context("sessions parent")?
            .join(storage_key("bot-child", "Thread")?);
        tokio::fs::create_dir_all(&child_session).await?;
        // A flat v2 child can be proven from canonical ancestry without a legacy manifest.
        let mut child_manifest = manifest;
        child_manifest["threadId"] = "bot-child".into();
        child_manifest.insert("parentThreadId".into(), THREAD.into());
        tokio::fs::write(
            child_session.join("session.toml"),
            toml::to_string(&child_manifest)?,
        )
        .await?;
        let checkpoint = bot_checkpoint("bot-child", frozen_bot, &frozen_root, true)?;
        tokio::fs::write(
            child_session.join("state.toml"),
            toml::to_string(&checkpoint)?,
        )
        .await?;
        let ledger = home.join("v2/bots/bot-test-one/state.sqlite");
        tokio::fs::create_dir_all(ledger.parent().context("ledger parent")?).await?;
        let mut db = sea_orm::sqlx::SqliteConnection::connect_with(
            &sea_orm::sqlx::sqlite::SqliteConnectOptions::new()
                .filename(&ledger)
                .create_if_missing(true),
        )
        .await?;
        db.execute("CREATE TABLE bot_meta(id INTEGER PRIMARY KEY, schema_version INTEGER); INSERT INTO bot_meta VALUES(1,6); CREATE TABLE thread_bindings(thread_id TEXT, project_id TEXT, status TEXT);").await?;
        sea_orm::sqlx::query("INSERT INTO thread_bindings VALUES (?,?, 'bound')")
            .bind(THREAD)
            .bind(OWNER)
            .execute(&mut db)
            .await?;
        db.close().await?;
        Ok((paths, old_root))
    }

    async fn frozen_workspace_identity(home: &Path, root: &str) -> Result<()> {
        let database = home.join("v2/studio.sqlite");
        wal_family(&database, true).await?;
        let mut db = sea_orm::sqlx::SqliteConnection::connect_with(
            &sea_orm::sqlx::sqlite::SqliteConnectOptions::new().filename(&database),
        )
        .await?;
        let payload =
        serde_json::json!({"owner":THREAD,"identity":{"endpoint":{"kind":"local"},"root":root}})
            .to_string();
        sea_orm::sqlx::query("INSERT INTO studio_objects(owner_kind,owner_id,object_kind,revision,schema_version,payload_json,payload_hash,updated_at) VALUES ('thread',?,'workspaceIdentity',1,1,?,?,42)")
        .bind(THREAD).bind(&payload).bind(pl_core::context::content_hash(payload.as_bytes())).execute(&mut db).await?;
        db.close().await?;
        Ok(())
    }

    fn bot_completion_path(root: &Path, thread: &str) -> PathBuf {
        root.join(pl_tool::workspace::SessionFiles::new(thread).root())
            .join(".migration-complete")
    }

    async fn associate_managed_bot_project(paths: &StudioPaths, old_root: &str) -> Result<()> {
        let legacy = paths.home().join("v2");
        let workspace_file = legacy.join("workspaces.toml");
        let mut workspaces: toml::Table =
            toml::from_str(&tokio::fs::read_to_string(&workspace_file).await?)?;
        workspaces["workspaces"][0]["path"] = old_root.into();
        tokio::fs::write(workspace_file, toml::to_string(&workspaces)?).await?;
        let manifest_file = legacy
            .join("projects")
            .join(storage_key(OWNER, "Workspace")?)
            .join("project.toml");
        let mut manifest: toml::Table =
            toml::from_str(&tokio::fs::read_to_string(&manifest_file).await?)?;
        manifest["path"] = old_root.into();
        tokio::fs::write(manifest_file, toml::to_string(&manifest)?).await?;
        Ok(())
    }

    async fn bot_workspace_completion(paths: &StudioPaths, thread: &str) -> Result<bool> {
        let store = StudioStore::prepare_database(&paths.database()).await?;
        let writer = crate::studio::agent_host::ThreadWriteBehindWriter::new(store.clone());
        let events = crate::studio::ProductEventBus::new(store.clone(), writer.clone());
        let config = crate::config::ConfigRuntime::initialize(crate::config::ConfigStore::new(
            crate::config::ConfigPaths::from_config_dir(paths.home()),
        ))?;
        let bots = crate::bots::BotRuntime::new(paths.clone(), config, events)?;
        let config = crate::bots::load_config(&paths.bot_dir("bot-test-one").join("config.toml"))?;
        let associated = store
            .workspaces()
            .get(&config.workspace_id)
            .context("associated workspace")?;
        let result = bots
            .workspace_migration_complete(&config, thread, &associated.path)
            .await;
        bots.shutdown().await?;
        writer.shutdown().await?;
        store.close().await?;
        Ok(result?)
    }

    #[tokio::test]
    async fn proven_bot_root_and_child_relocate_only_typed_fields_on_demand() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let (paths, old_root) = bot_binding_fixture(temp.path(), "bot-test-one").await?;
        let frozen_root = std::fs::canonicalize(&old_root)?
            .to_str()
            .context("frozen root")?
            .to_owned();
        associate_managed_bot_project(&paths, &frozen_root).await?;
        frozen_workspace_identity(temp.path(), &frozen_root).await?;
        for thread in [THREAD, "bot-child"] {
            let marker = bot_completion_path(Path::new(&old_root), thread);
            tokio::fs::create_dir_all(marker.parent().context("completion parent")?).await?;
            let source = bot_completion_path(Path::new(&frozen_root), thread);
            let source = source.parent().context("completion source")?;
            tokio::fs::write(&marker, source.to_string_lossy().as_bytes()).await?;
        }
        prepare(&paths).await?;
        assert!(
            !Path::new(&old_root).exists(),
            "on-demand checkpoint relocation cannot resolve the moved source directory"
        );
        let mapping = bot_roots::for_history(
            &paths.session_paths(OWNER, THREAD)?.history_database(),
            THREAD,
        )
        .await?
        .context("published migration proof")?;
        assert_eq!(
            mapping.threads.len(),
            2,
            "eligible proofs survive TOML serialization"
        );
        assert!(
            mapping
                .threads
                .values()
                .all(|proof| proof.proven_local_root)
        );
        let new_root = paths
            .bot_dir("bot-test-one")
            .join("workspace")
            .to_str()
            .context("new root")?
            .to_owned();
        for thread in [THREAD, "bot-child"] {
            let marker = bot_completion_path(Path::new(&new_root), thread);
            assert_eq!(
                tokio::fs::read_to_string(&marker).await?,
                marker
                    .parent()
                    .context("current completion source")?
                    .to_string_lossy(),
                "the completion must follow the same proven root relocation"
            );
            assert!(bot_workspace_completion(&paths, thread).await?);
        }
        let journal =
            decode_journal(&tokio::fs::read_to_string(paths.home().join(JOURNAL)).await?)?;
        let preserved_root = backup_root(&paths, &journal).join("v2/bots/bot-test-one/workspace");
        for thread in [THREAD, "bot-child"] {
            assert_eq!(
                tokio::fs::read_to_string(bot_completion_path(&preserved_root, thread)).await?,
                bot_completion_path(Path::new(&frozen_root), thread)
                    .parent()
                    .context("original completion source")?
                    .to_string_lossy(),
                "the original completion in the migration backup must remain unchanged"
            );
        }
        let catalog: toml::Table =
            toml::from_str(&tokio::fs::read_to_string(paths.catalog_file()).await?)?;
        assert_eq!(
            catalog["revision"].as_integer(),
            Some(9),
            "representation maintenance keeps product revision"
        );
        let workspace: toml::Table =
            toml::from_str(&tokio::fs::read_to_string(paths.workspaces_file()).await?)?;
        assert_eq!(
            workspace["workspaces"][0]["path"].as_str(),
            Some(new_root.as_str()),
            "the bot-owned project and completion use the same relocated source"
        );
        let store = StudioStore::prepare_database(&paths.database()).await?;
        assert_eq!(
            store.paths().home(),
            paths.home(),
            "database preparation must preserve the migration home's logical identity"
        );
        assert_eq!(
            store
                .workspace_identity(THREAD)
                .await?
                .context("frozen identity")?
                .root,
            new_root
        );
        for (thread, child) in [(THREAD, false), ("bot-child", true)] {
            // 工作区路径是会话级目录事实；两名成员共用同一会话记录。
            assert_eq!(
                store
                    .catalog()
                    .get_session(THREAD)
                    .context("catalog")?
                    .workspace_path,
                new_root
            );
            let history = store.history_for(OWNER, thread).await?;
            if child {
                store
                    .state_for(OWNER, thread)?
                    .prepare_recovery(&history)
                    .await?;
            }
            let checkpoint = history
                .prepare_model_access()
                .await?
                .context("checkpoint")?;
            assert_eq!(checkpoint.history_fence, 0);
            assert_eq!(checkpoint.state_revision, 0);
            let project = &checkpoint.state.extensions["studio.project"];
            assert_eq!(project.revision, 5);
            let record: crate::studio::WorkspaceRecord =
                serde_json::from_str(project.payload.content())?;
            assert_eq!(record.path, new_root);
            assert_eq!(record.id, OWNER);
            assert_eq!(
                checkpoint.state.extensions["unrelated.opaque"]
                    .payload
                    .content(),
                format!("original path string: {frozen_root}")
            );
            if child {
                let assignment =
                    crate::studio::workspace_receipt::from_snapshot(&checkpoint.state)?
                        .context("assignment")?;
                assert_eq!(assignment.root, new_root);
                assert_eq!(assignment.project_root, new_root);
                assert_eq!(assignment.writable_paths, Some(Vec::new()));
                assert_eq!(checkpoint.state.extensions["studio.workspace"].revision, 9);
            }
            assert_eq!(
                serde_json::to_value(history.prepare_model_access().await?.context("restart")?)?,
                serde_json::to_value(checkpoint)?
            );
        }
        store.close().await?;
        Ok(())
    }

    async fn upgrade_bot_completions_at_publication_boundary(published: bool) -> Result<()> {
        let temp = tempfile::tempdir()?;
        let (paths, old_root) = bot_binding_fixture(temp.path(), "bot-test-one").await?;
        associate_managed_bot_project(&paths, &old_root).await?;
        prepare(&paths).await?;
        let new_root = paths.bot_dir("bot-test-one").join("workspace");
        let marker = bot_completion_path(&new_root, THREAD);
        tokio::fs::create_dir_all(marker.parent().context("completion parent")?).await?;
        let original = bot_completion_path(Path::new(&old_root), THREAD)
            .parent()
            .context("old completion source")?
            .to_string_lossy()
            .into_owned();
        tokio::fs::write(&marker, &original).await?;
        let child_marker = bot_completion_path(&new_root, "bot-child");
        tokio::fs::create_dir_all(child_marker.parent().context("child completion parent")?)
            .await?;
        let created = r#"{"schemaVersion":1,"threadId":"bot-child"}"#;
        tokio::fs::write(&child_marker, created).await?;
        let unowned = bot_completion_path(&new_root, "not-a-bound-thread");
        tokio::fs::create_dir_all(unowned.parent().context("unowned parent")?).await?;
        tokio::fs::write(&unowned, &original).await?;
        let mut layout: Layout =
            toml::from_str(&tokio::fs::read_to_string(paths.layout_file()).await?)?;
        // An installation already published by the old application has an authoritative v1 layout.
        layout.schema_version = 1;
        persist(&paths.layout_file(), &layout).await?;
        let mut journal =
            decode_journal(&tokio::fs::read_to_string(paths.home().join(JOURNAL)).await?)?;
        journal.phase = Phase::Publishing;
        persist(&paths.home().join(JOURNAL), &journal).await?;
        let preserved = backup_root(&paths, &journal);
        if published {
            tokio::fs::rename(&preserved, paths.home().join("preserved-offline")).await?;
        } else {
            managed_move(paths.data_dir(), staging(&paths, &journal).data_dir()).await?;
        }

        prepare(&paths).await?;
        assert!(bot_workspace_completion(&paths, THREAD).await?);
        assert!(bot_workspace_completion(&paths, "bot-child").await?);
        assert_eq!(tokio::fs::read_to_string(&child_marker).await?, created);
        assert_eq!(tokio::fs::read_to_string(&unowned).await?, original);
        let upgraded = tokio::fs::read(paths.layout_file()).await?;
        assert_eq!(
            toml::from_str::<Layout>(std::str::from_utf8(&upgraded)?)?.schema_version,
            2
        );
        assert_eq!(
            decode_journal(&tokio::fs::read_to_string(paths.home().join(JOURNAL)).await?)?.phase,
            Phase::Completed
        );
        prepare(&paths).await?;
        assert_eq!(tokio::fs::read(paths.layout_file()).await?, upgraded);
        assert_eq!(
            tokio::fs::read_to_string(&marker).await?,
            marker
                .parent()
                .context("current completion source")?
                .to_string_lossy()
        );

        if published {
            // The child is converted before an IO failure at the root. Keep v1 until every write
            // succeeds, then resume without revisiting the unavailable source or undoing the child.
            let old_child = bot_completion_path(Path::new(&old_root), "bot-child");
            tokio::fs::write(
                &child_marker,
                old_child
                    .parent()
                    .context("old child source")?
                    .to_string_lossy()
                    .as_bytes(),
            )
            .await?;
            tokio::fs::remove_file(&marker).await?;
            tokio::fs::create_dir(&marker).await?;
            prepare(&paths).await?; // Current startup does not re-enumerate the completion files.
            persist(&paths.layout_file(), &layout).await?;
            assert!(prepare(&paths).await.is_err());
            assert_eq!(
                toml::from_str::<Layout>(&tokio::fs::read_to_string(paths.layout_file()).await?)?
                    .schema_version,
                1
            );
            assert!(bot_workspace_completion(&paths, "bot-child").await?);
            tokio::fs::remove_dir(&marker).await?;
            tokio::fs::write(&marker, &original).await?;
            prepare(&paths).await?;
            assert!(bot_workspace_completion(&paths, THREAD).await?);
        }

        // Missing and foreign receipts cannot acquire completion authority during a retry.
        tokio::fs::remove_file(&marker).await?;
        tokio::fs::remove_dir(marker.parent().context("empty completion directory")?).await?;
        let foreign = b"another-source\xff";
        tokio::fs::write(&child_marker, foreign).await?;
        persist(&paths.layout_file(), &layout).await?;
        prepare(&paths).await?;
        assert!(!marker.exists());
        assert!(
            !marker
                .parent()
                .context("missing completion directory")?
                .exists()
        );
        assert!(!bot_workspace_completion(&paths, THREAD).await?);
        assert!(bot_workspace_completion(&paths, "bot-child").await.is_err());
        assert_eq!(tokio::fs::read(&child_marker).await?, foreign);
        assert_eq!(tokio::fs::read_to_string(&unowned).await?, original);
        Ok(())
    }

    #[tokio::test]
    async fn legacy_bot_completions_upgrade_at_either_publication_boundary() -> Result<()> {
        for published in [false, true] {
            upgrade_bot_completions_at_publication_boundary(published).await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn prepared_history_without_checkpoint_recovers_verified_toml_and_keeps_sqlite_canonical()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let (paths, old_root) = bot_binding_fixture(temp.path(), "bot-test-one").await?;
        let sessions = temp
            .path()
            .join("v2/projects")
            .join(storage_key(OWNER, "Workspace")?)
            .join("sessions");
        let child = sessions.join(storage_key("bot-child", "Thread")?);
        prepared_history_family(&child.join("history.sqlite"), "bot-child", 7).await?;
        let mut original = bot_checkpoint("bot-child", "bot-test-one", &old_root, true)?;
        original.history_fence = 7;
        original.state_revision = 37;
        original.state.commit_sequence = 37;
        // Freeze an already-current delegation fact so this test isolates relocation rather than
        // the independent model-access migration that adds an absent delegation extension.
        original.state.extensions.insert(
            crate::studio::delegation::EXTENSION.into(),
            pl_core::thread::extensions::ExtensionRecord {
                revision: 8,
                payload: crate::studio::delegation::encode(Default::default())?,
            },
        );
        let (externalized, bodies) = original.externalize_bodies(0);
        assert!(!bodies.is_empty());
        tokio::fs::create_dir_all(child.join("blobs/checkpoint")).await?;
        for body in bodies {
            let hash = body
                .entry
                .reference
                .digest()
                .strip_prefix("sha256:")
                .context("body hash")?;
            let directory = child.join("blobs/checkpoint").join(&hash[..2]);
            tokio::fs::create_dir_all(&directory).await?;
            tokio::fs::write(directory.join(hash), body.bytes).await?;
        }
        let toml_bytes = toml::to_string(&externalized)?;
        tokio::fs::write(child.join("state.toml"), &toml_bytes).await?;
        // Root already has a committed SQLite checkpoint: even a contradictory/future stale TOML
        // must not supersede it or make owner evidence depend on the wrong source.
        tokio::fs::write(
            sessions
                .join(storage_key(THREAD, "Thread")?)
                .join("state.toml"),
            "schemaVersion = 999\nthreadId = 'stale-foreign-thread'\n",
        )
        .await?;
        prepare(&paths).await?;
        let session = paths.session_paths(OWNER, "bot-child")?;
        let mapping = bot_roots::for_history(&session.history_database(), "bot-child")
            .await?
            .context("published bot proof")?;
        assert!(mapping.threads["bot-child"].proven_local_root);
        let store = StudioStore::prepare_database(&paths.database()).await?;
        let history = store.history_for(OWNER, "bot-child").await?;
        store
            .state_for(OWNER, "bot-child")?
            .prepare_recovery(&history)
            .await?;
        let recovered = history
            .prepare_model_access()
            .await?
            .context("recovered checkpoint")?;
        assert_eq!(recovered.thread_id, original.thread_id);
        assert_eq!(recovered.history_fence, 7);
        assert_eq!(history.watermark().await?, 7);
        assert_eq!(recovered.state_revision, 37);
        assert_eq!(recovered.saved_at, original.saved_at);
        assert_eq!(
            recovered.state.extension_sequence,
            original.state.extension_sequence
        );
        assert_eq!(
            serde_json::to_value(&recovered.state.extensions["unrelated.opaque"])?,
            serde_json::to_value(&original.state.extensions["unrelated.opaque"])?
        );
        let assignment = crate::studio::workspace_receipt::from_snapshot(&recovered.state)?
            .context("child workspace assignment")?;
        assert_eq!(assignment.root, mapping.new_root);
        assert_eq!(assignment.project_root, mapping.new_root);
        assert_eq!(assignment.writable_paths, Some(Vec::new()));
        assert_eq!(recovered.state.extensions["studio.workspace"].revision, 9);
        let owner: crate::studio::WorkspaceRecord = serde_json::from_str(
            recovered.state.extensions["studio.project"]
                .payload
                .content(),
        )?;
        assert_eq!(owner.id, OWNER);
        assert_eq!(owner.path, mapping.new_root);
        assert_eq!(recovered.state.extensions["studio.project"].revision, 5);
        assert_eq!(
            store
                .workspaces()
                .get(OWNER)
                .context("business workspace")?
                .path,
            "/isolated-workspace"
        );
        let canonical_root = store.history_for(OWNER, THREAD).await?;
        assert_eq!(
            canonical_root
                .prepare_model_access()
                .await?
                .context("root checkpoint")?
                .thread_id,
            THREAD
        );
        assert_eq!(
            serde_json::to_value(history.prepare_model_access().await?.context("restart")?)?,
            serde_json::to_value(recovered)?
        );
        store.close().await?;
        let journal = decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
        assert_eq!(
            tokio::fs::read_to_string(
                backup_root(&paths, &journal)
                    .join(child.strip_prefix(temp.path())?)
                    .join("state.toml")
            )
            .await?,
            toml_bytes
        );
        Ok(())
    }

    #[tokio::test]
    async fn prepared_history_toml_window_rejects_unknown_or_conflicting_evidence() -> Result<()> {
        for fault in [
            "foreign-history",
            "future-history",
            "missing-checkpoint-table",
            "unversioned-history",
            "corrupt-history",
            "future-toml",
            "foreign-toml",
            "owner-conflict",
            "missing-body",
            "corrupt-toml",
        ] {
            let temp = tempfile::tempdir()?;
            let (paths, old_root) = bot_binding_fixture(temp.path(), "bot-test-one").await?;
            let child = temp
                .path()
                .join("v2/projects")
                .join(storage_key(OWNER, "Workspace")?)
                .join("sessions")
                .join(storage_key("bot-child", "Thread")?);
            let database = child.join("history.sqlite");
            let thread = if fault == "foreign-history" {
                "other-thread"
            } else {
                "bot-child"
            };
            prepared_history_family(&database, thread, 7).await?;
            let mut checkpoint = bot_checkpoint("bot-child", "bot-test-one", &old_root, true)?;
            checkpoint.history_fence = 7;
            checkpoint.state_revision = 37;
            checkpoint.state.commit_sequence = 37;
            match fault {
                "future-history" | "missing-checkpoint-table" => {
                    let mut db = sea_orm::sqlx::SqliteConnection::connect_with(
                        &sea_orm::sqlx::sqlite::SqliteConnectOptions::new().filename(&database),
                    )
                    .await?;
                    db.execute(if fault == "future-history" {
                        "UPDATE history_meta SET schema_version=999"
                    } else {
                        "DROP TABLE session_checkpoint"
                    })
                    .await?;
                    db.close().await?;
                }
                "unversioned-history" | "corrupt-history" => {
                    for suffix in ["", "-wal", "-shm"] {
                        let member = child.join(format!("history.sqlite{suffix}"));
                        if member.exists() {
                            tokio::fs::remove_file(member).await?;
                        }
                    }
                    tokio::fs::write(
                        &database,
                        if fault == "corrupt-history" {
                            b"not sqlite".as_slice()
                        } else {
                            &[]
                        },
                    )
                    .await?;
                }
                "future-toml" => checkpoint.schema_version = 999,
                "foreign-toml" => checkpoint.thread_id = "foreign-thread".into(),
                "owner-conflict" => {
                    checkpoint = bot_checkpoint("bot-child", "bot-other", &old_root, true)?
                }
                "missing-body" => {
                    checkpoint = checkpoint.externalize_bodies(0).0;
                    assert!(!checkpoint.external_bodies.is_empty());
                }
                _ => {}
            }
            let content = if fault == "corrupt-toml" {
                "broken = [".to_owned()
            } else {
                toml::to_string(&checkpoint)?
            };
            tokio::fs::write(child.join("state.toml"), &content).await?;
            for _ in 0..2 {
                prepare(&paths).await.expect_err(fault);
                assert!(!paths.layout_file().exists(), "{fault}");
            }
            let journal =
                decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
            assert_eq!(
                tokio::fs::read_to_string(
                    backup_root(&paths, &journal)
                        .join(child.strip_prefix(temp.path())?)
                        .join("state.toml")
                )
                .await?,
                content
            );
        }
        Ok(())
    }

    #[tokio::test]
    async fn nonmanaged_identity_is_preserved_with_execution_diagnostic_and_readable_history()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let (paths, old_root) = bot_binding_fixture(temp.path(), "bot-test-one").await?;
        let marker = bot_completion_path(Path::new(&old_root), THREAD);
        tokio::fs::create_dir_all(marker.parent().context("completion parent")?).await?;
        let completion = marker
            .parent()
            .context("old completion source")?
            .to_string_lossy()
            .into_owned();
        tokio::fs::write(&marker, &completion).await?;
        let business_root = temp.path().join("business-project-not-owned-by-bot");
        tokio::fs::create_dir_all(&business_root).await?;
        let business_root = dunce::canonicalize(&business_root)?
            .to_str()
            .context("business root")?
            .to_owned();
        frozen_workspace_identity(temp.path(), &business_root).await?;
        prepare(&paths).await?;
        assert_eq!(
            tokio::fs::read_to_string(bot_completion_path(
                &paths.bot_dir("bot-test-one").join("workspace"),
                THREAD,
            ))
            .await?,
            completion,
            "a blocked physical identity cannot grant a migrated completion"
        );
        let store = StudioStore::prepare_database(&paths.database()).await?;
        assert_eq!(
            store
                .workspaces()
                .get(OWNER)
                .context("business project")?
                .path,
            "/isolated-workspace",
            "the unrelated business project must retain its original address"
        );
        assert_eq!(
            store
                .workspace_identity(THREAD)
                .await?
                .context("preserved identity")?
                .root,
            business_root
        );
        let history = store.history_for(OWNER, THREAD).await?;
        assert!(
            history.checkpoint().await?.is_some(),
            "content reads do not require execution rebinding"
        );
        let error = history
            .prepare_model_access()
            .await
            .expect_err("unsafe execution must be refused");
        assert!(
            format!("{error:#}").contains("original binding was preserved"),
            "{error:#}"
        );
        assert!(history.checkpoint().await?.is_some());
        store.close().await?;
        prepare(&paths).await?;
        Ok(())
    }

    #[tokio::test]
    async fn conflicting_bot_owner_evidence_preserves_sources_without_publication() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let (paths, _) = bot_binding_fixture(temp.path(), "bot-conflicting-owner").await?;
        for _ in 0..2 {
            assert!(prepare(&paths).await.is_err());
            assert!(!paths.layout_file().exists());
        }
        let journal = decode_journal(&tokio::fs::read_to_string(temp.path().join(JOURNAL)).await?)?;
        assert!(
            backup_root(&paths, &journal)
                .join("v2/bots/bot-test-one/state.sqlite")
                .exists()
        );
        Ok(())
    }

    #[tokio::test]
    async fn layout_failure_through_runtime_archives_migration_before_default_startup() -> Result<()>
    {
        let temp = tempfile::tempdir()?;
        let (paths, source) = fixture(temp.path(), false, false).await?;
        tokio::fs::write(source.join("attachments.toml"), b"bad = [").await?;
        let options = crate::StudioRuntimeOptions {
            studio_home: Some(temp.path().to_owned()),
            host: crate::StudioHostKind::Test,
            ..crate::StudioRuntimeOptions::desktop()
        };
        let runtime = crate::StudioRuntime::initialize(options.clone()).await?;
        let snapshot = runtime.runtime_snapshot().await?;
        let report = snapshot
            .startup_recovery
            .as_ref()
            .context("recovery reported")?;
        let archived = PathBuf::from(&report.backup_path).join("original");
        let journal = decode_journal(&tokio::fs::read_to_string(archived.join(JOURNAL)).await?)?;
        let original = archived
            .join(backup_root(&paths, &journal).strip_prefix(temp.path())?)
            .join(source.strip_prefix(temp.path())?);
        assert_eq!(
            tokio::fs::read(original.join("attachments.toml")).await?,
            b"bad = ["
        );
        assert!(paths.layout_file().exists());
        assert!(
            runtime
                .list_threads_page(None, 100)
                .await?
                .state
                .value()
                .context("ready directory")?
                .rows
                .is_empty()
        );
        runtime.shutdown_runtime().await?;
        let reopened = crate::StudioRuntime::initialize(options).await?;
        assert!(
            reopened
                .runtime_snapshot()
                .await?
                .startup_recovery
                .is_none()
        );
        reopened.shutdown_runtime().await?;
        assert_eq!(
            std::fs::read_dir(temp.path().join("startup-backups"))?.count(),
            1
        );
        assert!(!temp.path().join("startup-recovery.toml").exists());
        Ok(())
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn linked_sources_and_target_ancestors_fail_without_following_them() -> Result<()> {
        for source_link in [true, false] {
            let temp = tempfile::tempdir()?;
            let outside = tempfile::tempdir()?;
            let (paths, session) = fixture(temp.path(), false, false).await?;
            let sentinel = outside.path().join("sentinel");
            tokio::fs::write(&sentinel, b"unrelated bytes").await?;
            if source_link {
                std::os::unix::fs::symlink(&sentinel, session.join("thread-resources/link"))?;
            } else {
                std::os::unix::fs::symlink(outside.path(), paths.data_dir())?;
            }
            assert!(prepare(&paths).await.is_err());
            assert!(!paths.layout_file().exists());
            assert_eq!(tokio::fs::read(&sentinel).await?, b"unrelated bytes");
        }
        Ok(())
    }
}

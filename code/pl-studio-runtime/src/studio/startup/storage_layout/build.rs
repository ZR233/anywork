//! Validate and copy preserved v2 sources into the unpublished layout.

use std::collections::{BTreeMap, BTreeSet};

use super::bot_roots;
use super::files::{copy_tree, ensure_tree_safe, original_path, validate_family};
use super::{Journal, optional_text, persist};
use crate::studio::catalog::CatalogStore;
use crate::studio::paths::{StudioPaths, storage_key};
use crate::studio::store::{attachment, session_layout, workspaces};
use anyhow::{Context, Result, ensure};
use serde::Deserialize;
use session_layout::{SessionManifest, WorkspaceManifest};
use std::path::{Path, PathBuf};

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

pub(super) async fn build(
    paths: &StudioPaths,
    stage: &StudioPaths,
    backup: &Path,
    journal_path: &Path,
    journal: &mut Journal,
) -> Result<PreparedLayoutDatabase> {
    let roots = [backup.join("v2"), backup.join("studio/v2")];
    let source = classify_sources(&roots)?;
    copy_documents(stage, &roots, &source).await?;
    copy_global_domains(paths, stage, &roots, journal_path, journal).await?;
    if matches!(source, SourceInstallation::V2) {
        copy_directory(paths, stage, &roots, journal_path, journal).await?;
    }
    // A fresh operation may resume its own partly-created target, but never adopt an orphan WAL.
    // Source families, copy hashes and ownership were checked above, independently of target state.
    validate_family(&stage.database())?;
    validate_family(&stage.calls_database())?;
    Ok(PreparedLayoutDatabase {
        path: stage.database(),
        source,
    })
}

fn classify_sources(roots: &[PathBuf]) -> Result<SourceInstallation> {
    // Directory existence is not installation evidence: a cache-only v2 home never owned
    // canonical state. Conversely, any other material must not be adopted as a fresh install.
    let mut has_v2 = false;
    for root in roots {
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
                existing_candidates(roots, name)?.len() == 1,
                "v2 authoritative {name} missing or duplicated"
            );
        }
    }
    Ok(if has_v2 {
        SourceInstallation::V2
    } else {
        SourceInstallation::Fresh
    })
}

async fn copy_documents(
    stage: &StudioPaths,
    roots: &[PathBuf],
    source: &SourceInstallation,
) -> Result<()> {
    for name in ["settings.toml", "workspaces.toml", "catalog.toml"] {
        let candidates = existing_candidates(roots, name)?;
        if matches!(source, SourceInstallation::V2) {
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
    Ok(())
}

async fn copy_global_domains(
    paths: &StudioPaths,
    stage: &StudioPaths,
    roots: &[PathBuf],
    journal_path: &Path,
    journal: &mut Journal,
) -> Result<()> {
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
        let candidates = existing_candidates(roots, name)?;
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
                use crate::studio::paths::sqlite_family_paths;
                for (member, destination) in sqlite_family_paths(source)
                    .into_iter()
                    .zip(sqlite_family_paths(&target))
                {
                    if member.try_exists()? {
                        copy_tree(paths.home(), &member, &destination).await?;
                    }
                }
            } else {
                copy_tree(paths.home(), source, &target).await?;
            }
        } else if name == "studio.sqlite" {
            for root in roots {
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
    Ok(())
}

async fn copy_directory(
    paths: &StudioPaths,
    stage: &StudioPaths,
    roots: &[PathBuf],
    journal_path: &Path,
    journal: &mut Journal,
) -> Result<()> {
    let catalog = CatalogStore::load(stage.catalog_file()).await?;
    let workspaces = workspaces::WorkspaceStore::load(stage.workspaces_file()).await?;
    catalog.validate_workspace_references(&workspaces)?;
    let layout_root = existing_candidates(roots, "projects")?;
    let flat_roots = existing_candidates(roots, "sessions")?;
    ensure!(
        layout_root.len() <= 1 && flat_roots.len() <= 1,
        "ambiguous v2 session roots"
    );
    let legacy_journal = load_legacy_journal(roots, &catalog, &workspaces).await?;
    let mut relocations = bot_roots::plan(paths, stage, roots, &catalog).await?;
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
    copy_workspace_manifests(stage, layout_root.first(), &workspaces, &journal.bot_roots).await?;
    copy_sessions(
        paths,
        stage,
        SessionSources {
            grouped: layout_root.first(),
            flat: flat_roots.first(),
            legacy_journal: &legacy_journal,
        },
        &catalog,
        journal_path,
        journal,
    )
    .await?;
    crate::studio::catalog::relocate_managed_v2_paths(&stage.catalog_file(), &journal.bot_roots)
        .await?;
    Ok(())
}

async fn copy_workspace_manifests(
    stage: &StudioPaths,
    grouped: Option<&PathBuf>,
    workspaces: &workspaces::WorkspaceStore,
    bot_roots: &[bot_roots::BotRootMove],
) -> Result<()> {
    for workspace in workspaces.entries() {
        let mut expected = WorkspaceManifest {
            schema_version: 2,
            workspace_id: workspace.id.clone(),
            kind: workspace.kind,
            path: workspace.path.clone(),
            ssh_alias: workspace.ssh_alias.clone(),
        };
        if let Some(root) = grouped {
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
        if let Some(mapping) = bot_roots.iter().find(|mapping| {
            mapping.workspace_id == workspace.id
                && workspace.ssh_alias.is_none()
                && bot_roots::same_path(Path::new(&workspace.path), Path::new(&mapping.old_root))
                && mapping
                    .threads
                    .values()
                    .any(|proof| proof.proven_local_root)
        }) {
            expected.path = mapping.new_root.clone();
        }
        session_layout::persist_workspace_manifest(stage, &expected).await?;
    }
    Ok(())
}

struct SessionSources<'a> {
    grouped: Option<&'a PathBuf>,
    flat: Option<&'a PathBuf>,
    legacy_journal: &'a BTreeMap<String, LegacyMove>,
}

async fn copy_sessions(
    paths: &StudioPaths,
    stage: &StudioPaths,
    sources: SessionSources<'_>,
    catalog: &CatalogStore,
    journal_path: &Path,
    journal: &mut Journal,
) -> Result<()> {
    for (mut session, agent) in catalog_directory_threads(catalog) {
        let key = storage_key(&agent.thread_id, "Thread")?;
        let owner_key = storage_key(&session.workspace_id, "Workspace")?;
        let grouped = sources
            .grouped
            .map(|root| root.join(&owner_key).join("sessions").join(&key));
        let flat = sources.flat.map(|root| root.join(&key));
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
        if let Some(item) = sources.legacy_journal.get(&agent.thread_id)
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
            SessionManifest::from_directory_facts(&session, &agent, |id| catalog.get_agent(id))?;
        if let Some(mapping) = journal.bot_roots.iter().find(|mapping| {
            mapping
                .threads
                .get(&agent.thread_id)
                .is_some_and(|proof| proof.proven_local_root)
        }) {
            session.workspace_path = mapping.new_root.clone();
        }
        let expected =
            SessionManifest::from_directory_facts(&session, &agent, |id| catalog.get_agent(id))?;
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
            let previous_flat = if sources.legacy_journal.contains_key(&agent.thread_id) {
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
                crate::studio::paths::is_sha256_hex(&name) && entry.file_type().await?.is_file(),
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
                    && crate::studio::paths::is_sha256_hex(&record.content_sha256),
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

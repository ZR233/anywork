//! Project/session ownership manifests and the v2 flat-session layout migration.
//!
//! Manifests describe only versioned identity and fixed binding. Variable title, name and
//! route stay in catalog/checkpoint. Layout migration runs after canonical catalog and
//! workspaces are loaded, before writers and services are published.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, ensure};
use pl_protocol::ThreadWorkspaceMode;
use serde::{Deserialize, Serialize};

use crate::studio::catalog::CatalogStore;
use crate::studio::paths::{SessionPaths, StudioPaths, posix_relative, storage_key};
use crate::studio::records::WorkspaceRecord;
use crate::studio::store::workspaces::WorkspaceStore;
use crate::studio::store::{SessionLayoutMigrationFailed, StudioStore};

mod schema;

pub(crate) const PROJECT_MANIFEST_SCHEMA_VERSION: u32 = 1;
pub(crate) const SESSION_MANIFEST_SCHEMA_VERSION: u32 = 1;
pub(crate) const LAYOUT_JOURNAL_SCHEMA_VERSION: u32 = 1;
const LAYOUT_JOURNAL_FILE_NAME: &str = "session-project-layout.toml";
const LAYOUT_MARKER_FILE_NAME: &str = "session-project-layout.complete";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct ProjectManifest {
    pub(crate) schema_version: u32,
    pub(crate) workspace_id: String,
    pub(crate) path: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) ssh_alias: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct SessionManifest {
    pub(crate) schema_version: u32,
    pub(crate) thread_id: String,
    pub(crate) workspace_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) parent_thread_id: Option<String>,
    pub(crate) root_thread_id: String,
    pub(crate) workspace_mode: ThreadWorkspaceMode,
    pub(crate) workspace_path: String,
    pub(crate) created_at: i64,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) enum LayoutMovePhase {
    Planned,
    Moved,
    Verified,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LayoutMove {
    thread_id: String,
    workspace_id: String,
    source_key: String,
    target_project_key: String,
    target_thread_key: String,
    phase: LayoutMovePhase,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LayoutJournal {
    schema_version: u32,
    completed: bool,
    orphans: Vec<String>,
    moves: Vec<LayoutMove>,
}

impl StudioStore {
    /// Typed session paths for an already registered catalog Thread.
    ///
    /// Unknown Threads fail instead of guessing a default Project.
    pub(crate) fn registered_session_paths(&self, thread_id: &str) -> Result<SessionPaths> {
        let workspace_id = self
            .catalog()
            .get(thread_id)
            .map(|entry| entry.workspace_id)
            .context("Thread is not registered in the Studio catalog")?;
        self.paths.session_paths(&workspace_id, thread_id)
    }

    /// Typed session paths from an explicit Project + Thread identity.
    ///
    /// Child prepare must use this before catalog publication.
    pub(crate) fn session_paths(&self, workspace_id: &str, thread_id: &str) -> Result<SessionPaths> {
        self.paths.session_paths(workspace_id, thread_id)
    }

    /// Materialize a project identity manifest before publishing catalog facts.
    ///
    /// An existing matching manifest is left in place. A conflicting manifest fails closed.
    pub(crate) async fn prepare_project_manifest(&self, project: &WorkspaceRecord) -> Result<()> {
        let expected = ProjectManifest {
            schema_version: PROJECT_MANIFEST_SCHEMA_VERSION,
            workspace_id: project.id.clone(),
            path: project.path.clone(),
            ssh_alias: project.ssh_alias.clone(),
        };
        persist_project_manifest(&self.paths, &expected).await
    }

    /// Materialize a session identity manifest before publishing catalog facts.
    pub(crate) async fn prepare_session_manifest(
        &self,
        thread: &pl_protocol::Thread,
    ) -> Result<SessionPaths> {
        let expected = SessionManifest {
            schema_version: SESSION_MANIFEST_SCHEMA_VERSION,
            thread_id: thread.id.clone(),
            workspace_id: thread.workspace_id.clone(),
            parent_thread_id: thread.parent_thread_id.clone(),
            root_thread_id: thread.root_thread_id.clone(),
            workspace_mode: thread.workspace_mode,
            workspace_path: thread.workspace_path.clone(),
            created_at: thread.created_at,
        };
        let session = persist_session_manifest(&self.paths, &expected).await?;
        let scratch = self.session_scratch_dir_for(&expected.workspace_id, &expected.thread_id)?;
        if !tokio::fs::try_exists(&scratch).await? {
            tokio::fs::create_dir_all(&scratch).await?;
        }
        Ok(session)
    }
}

pub(crate) async fn persist_project_manifest(
    paths: &StudioPaths,
    expected: &ProjectManifest,
) -> Result<()> {
    ensure!(
        expected.schema_version == PROJECT_MANIFEST_SCHEMA_VERSION,
        "unsupported project manifest schema"
    );
    ensure!(
        !expected.workspace_id.is_empty() && !expected.path.is_empty(),
        "project manifest identity is incomplete"
    );
    let directory = paths.project_dir(&expected.workspace_id)?;
    let path = paths.project_manifest(&expected.workspace_id)?;
    ensure_layout_write_path(paths, &directory).await?;
    ensure_layout_write_path(paths, &path).await?;
    tokio::fs::create_dir_all(&directory).await?;
    match tokio::fs::read_to_string(&path).await {
        Ok(content) => {
            let existing = decode_project_manifest(&path, &content)?;
            (|| {
                ensure!(
                    existing == *expected,
                    "existing project manifest does not match the identity being published"
                );
                Ok(())
            })()
            .map_err(|error: anyhow::Error| {
                crate::toml_schema::migration_error(
                    &path,
                    "project-manifest",
                    Some(PROJECT_MANIFEST_SCHEMA_VERSION),
                    PROJECT_MANIFEST_SCHEMA_VERSION,
                    "validate",
                    error,
                )
            })?;
            Ok(())
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            write_manifest_toml(&path, schema::encode_project(expected)?).await
        }
        Err(error) => Err(error.into()),
    }
}

pub(crate) async fn persist_session_manifest(
    paths: &StudioPaths,
    expected: &SessionManifest,
) -> Result<SessionPaths> {
    ensure!(
        expected.schema_version == SESSION_MANIFEST_SCHEMA_VERSION,
        "unsupported session manifest schema"
    );
    ensure!(
        !expected.thread_id.is_empty()
            && !expected.workspace_id.is_empty()
            && !expected.root_thread_id.is_empty(),
        "session manifest identity is incomplete"
    );
    if expected.parent_thread_id.is_none() {
        ensure!(
            expected.root_thread_id == expected.thread_id,
            "root session manifest is not its own root"
        );
    }
    let session = paths.session_paths(&expected.workspace_id, &expected.thread_id)?;
    ensure!(
        session.workspace_id() == expected.workspace_id && session.thread_id() == expected.thread_id,
        "session path identity drifted from the manifest"
    );
    persist_session_manifest_in(paths, session.root(), expected).await?;
    ensure_layout_write_path(paths, &session.session_manifest()).await?;
    Ok(session)
}

fn ensure_session_manifest_compatible(
    path: &Path,
    existing: &SessionManifest,
    expected: &SessionManifest,
) -> Result<()> {
    (|| {
        ensure!(
            existing.thread_id == expected.thread_id
                && existing.workspace_id == expected.workspace_id
                && existing.parent_thread_id == expected.parent_thread_id
                && existing.root_thread_id == expected.root_thread_id
                && existing.workspace_mode == expected.workspace_mode
                && existing.workspace_path == expected.workspace_path
                && existing.created_at == expected.created_at,
            "existing session manifest does not match the identity being published"
        );
        Ok(())
    })()
    .map_err(|error: anyhow::Error| {
        crate::toml_schema::migration_error(
            path,
            "session-manifest",
            Some(SESSION_MANIFEST_SCHEMA_VERSION),
            SESSION_MANIFEST_SCHEMA_VERSION,
            "validate",
            error,
        )
    })
}

/// Migrates leftover `v2/sessions/<thread-key>` directories into the project layout.
///
/// Failures are typed layout errors and must not trigger the global startup backup reset.
pub(crate) async fn migrate_flat_sessions(
    paths: &StudioPaths,
    catalog: &CatalogStore,
    workspaces: &WorkspaceStore,
) -> Result<()> {
    migrate_flat_sessions_inner(paths, catalog, workspaces)
        .await
        .map_err(layout_error)
}

async fn migrate_flat_sessions_inner(
    paths: &StudioPaths,
    catalog: &CatalogStore,
    workspaces: &WorkspaceStore,
) -> Result<()> {
    let journal_path = paths.migrations_dir().join(LAYOUT_JOURNAL_FILE_NAME);
    let marker_path = paths.migrations_dir().join(LAYOUT_MARKER_FILE_NAME);
    ensure_layout_write_path(paths, &journal_path).await?;
    ensure_layout_write_path(paths, &marker_path).await?;
    let marker = load_optional_marker(&marker_path).await?;
    let journal = load_optional_journal(&journal_path).await?;
    match (marker, journal) {
        (Some(marker), Some(journal)) => {
            validate_complete_marker(&marker)?;
            validate_completed_journal(paths, catalog, workspaces, &journal).await?;
            Ok(())
        }
        (Some(_), None) => bail_layout("layout completion marker exists without a journal"),
        (None, Some(journal)) if journal_is_complete(&journal) => {
            validate_completed_journal(paths, catalog, workspaces, &journal).await?;
            persist_marker(&marker_path).await?;
            Ok(())
        }
        (None, journal) => {
            let mut journal = match journal {
                Some(journal) => {
                    validate_journal_bindings(paths, catalog, workspaces, &journal)?;
                    journal
                }
                None => plan_journal(paths, catalog, workspaces).await?,
            };
            ensure_layout_write_path(paths, &paths.migrations_dir()).await?;
            tokio::fs::create_dir_all(paths.migrations_dir()).await?;
            persist_journal(&journal_path, &journal).await?;
            for index in 0..journal.moves.len() {
                apply_move(
                    paths,
                    catalog,
                    workspaces,
                    &journal_path,
                    &mut journal,
                    index,
                )
                .await?;
            }
            journal.completed = true;
            persist_journal(&journal_path, &journal).await?;
            persist_marker(&marker_path).await?;
            if !journal.orphans.is_empty() {
                tracing::warn!(
                    orphans = journal.orphans.len(),
                    "unregistered v2 session directories were left in place"
                );
            }
            Ok(())
        }
    }
}

fn bail_layout(message: &str) -> Result<()> {
    Err(anyhow::anyhow!("{message}"))
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LayoutCompleteMarker {
    schema_version: u32,
    completed: bool,
}

async fn plan_journal(
    paths: &StudioPaths,
    catalog: &CatalogStore,
    workspaces: &WorkspaceStore,
) -> Result<LayoutJournal> {
    let mut moves = Vec::new();
    let mut orphans = Vec::new();
    let legacy_root = paths.legacy_sessions_dir();
    if !tokio::fs::try_exists(&legacy_root).await? {
        return Ok(LayoutJournal {
            schema_version: LAYOUT_JOURNAL_SCHEMA_VERSION,
            completed: true,
            orphans,
            moves,
        });
    }
    ensure_layout_write_path(paths, &legacy_root).await?;
    let mut entries = tokio::fs::read_dir(&legacy_root).await?;
    let catalog_by_key = catalog
        .entries()
        .into_iter()
        .map(|entry| storage_key(&entry.id, "Thread").map(|key| (key, entry)))
        .collect::<Result<Vec<_>>>()?;
    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        let metadata = tokio::fs::symlink_metadata(&path).await?;
        if pl_tool::workspace::path_safety::is_link_or_reparse(&metadata) {
            anyhow::bail!(
                "legacy session path is a symlink or reparse point: {}",
                path.display()
            );
        }
        if !metadata.is_dir() {
            continue;
        }
        let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
            orphans.push(path.display().to_string());
            continue;
        };
        match catalog_by_key.iter().find(|(key, _)| key == name) {
            Some((_, entry)) => {
                ensure!(
                    workspaces.get(&entry.workspace_id).is_some(),
                    "catalog references a missing project during layout migration"
                );
                let thread_key = storage_key(&entry.id, "Thread")?;
                moves.push(LayoutMove {
                    thread_id: entry.id.clone(),
                    workspace_id: entry.workspace_id.clone(),
                    source_key: thread_key.clone(),
                    target_project_key: storage_key(&entry.workspace_id, "Project")?,
                    target_thread_key: thread_key,
                    phase: LayoutMovePhase::Planned,
                });
            }
            None => orphans.push(name.to_owned()),
        }
    }
    moves.sort_by(|left, right| left.thread_id.cmp(&right.thread_id));
    Ok(LayoutJournal {
        schema_version: LAYOUT_JOURNAL_SCHEMA_VERSION,
        completed: moves.is_empty(),
        orphans,
        moves,
    })
}

async fn apply_move(
    paths: &StudioPaths,
    catalog: &CatalogStore,
    workspaces: &WorkspaceStore,
    journal_path: &Path,
    journal: &mut LayoutJournal,
    index: usize,
) -> Result<()> {
    validate_move_item(paths, catalog, workspaces, &journal.moves[index])?;
    let source = paths
        .legacy_sessions_dir()
        .join(&journal.moves[index].source_key);
    let session = paths.session_paths(
        &journal.moves[index].workspace_id,
        &journal.moves[index].thread_id,
    )?;
    let target = session.root().to_path_buf();
    match journal.moves[index].phase {
        LayoutMovePhase::Planned => {
            prepare_move(
                paths,
                catalog,
                workspaces,
                &journal.moves[index],
                &source,
                &target,
            )
            .await?;
            journal.moves[index].phase = LayoutMovePhase::Moved;
            persist_journal(journal_path, journal).await?;
            verify_move(
                paths,
                catalog,
                workspaces,
                &journal.moves[index],
                &source,
                &session,
            )
            .await?;
            journal.moves[index].phase = LayoutMovePhase::Verified;
            persist_journal(journal_path, journal).await?;
        }
        LayoutMovePhase::Moved => {
            verify_move(
                paths,
                catalog,
                workspaces,
                &journal.moves[index],
                &source,
                &session,
            )
            .await?;
            journal.moves[index].phase = LayoutMovePhase::Verified;
            persist_journal(journal_path, journal).await?;
        }
        LayoutMovePhase::Verified => {
            ensure_verified_directories(paths, catalog, workspaces, &journal.moves[index]).await?;
        }
    }
    Ok(())
}

async fn prepare_move(
    paths: &StudioPaths,
    catalog: &CatalogStore,
    workspaces: &WorkspaceStore,
    item: &LayoutMove,
    source: &Path,
    target: &Path,
) -> Result<()> {
    let source_exists = path_exists_including_links(source).await?;
    let target_exists = path_exists_including_links(target).await?;
    match (source_exists, target_exists) {
        (true, false) => {
            ensure_layout_write_path(paths, source).await?;
            persist_session_manifest_in(
                paths,
                source,
                &expected_session_manifest(catalog, workspaces, item)?,
            )
            .await?;
            let parent = target.parent().context("session target has no parent")?;
            ensure_layout_write_path(paths, parent).await?;
            tokio::fs::create_dir_all(parent).await?;
            ensure_layout_write_path(paths, target).await?;
            tokio::task::spawn_blocking({
                let source = source.to_path_buf();
                let target = target.to_path_buf();
                move || pl_tool::workspace::move_owned_path(&source, &target)
            })
            .await??;
        }
        (false, true) => {
            ensure_absent_source(source).await?;
            ensure_safe_session_directory(paths, target).await?;
            load_matching_session_manifest(
                target,
                &expected_session_manifest(catalog, workspaces, item)?,
            )
            .await?;
        }
        (true, true) => {
            anyhow::bail!(
                "session layout target already exists and was not moved by this journal: {}",
                target.display()
            );
        }
        (false, false) => {
            anyhow::bail!("session layout source is missing: {}", source.display());
        }
    }
    Ok(())
}

async fn verify_move(
    paths: &StudioPaths,
    catalog: &CatalogStore,
    workspaces: &WorkspaceStore,
    item: &LayoutMove,
    source: &Path,
    session: &SessionPaths,
) -> Result<()> {
    ensure_absent_source(source).await?;
    ensure_safe_session_directory(paths, session.root()).await?;
    let catalog_entry = catalog_binding(catalog, workspaces, item)?;
    let workspace = workspaces
        .get(&item.workspace_id)
        .context("layout move references a missing project")?;
    persist_project_manifest(
        paths,
        &ProjectManifest {
            schema_version: PROJECT_MANIFEST_SCHEMA_VERSION,
            workspace_id: catalog_entry.workspace_id.clone(),
            path: workspace.path.clone(),
            ssh_alias: workspace.ssh_alias.clone(),
        },
    )
    .await?;
    load_matching_session_manifest(
        session.root(),
        &expected_session_manifest(catalog, workspaces, item)?,
    )
    .await?;
    migrate_attachment_catalog(paths, source, session.root(), session.thread_id()).await?;
    Ok(())
}

async fn migrate_attachment_catalog(
    paths: &StudioPaths,
    source_root: &Path,
    target_root: &Path,
    thread_id: &str,
) -> Result<()> {
    let path = target_root.join("attachments.toml");
    ensure_layout_write_path(paths, &path).await?;
    let content = match tokio::fs::read_to_string(&path).await {
        Ok(content) => content,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error.into()),
    };
    let mut catalog = crate::studio::store::attachment::decode_attachment_catalog(&path, &content)?;
    let source_blobs = source_root.join("blobs");
    let target_blobs = target_root.join("blobs");
    let mut changed = false;
    let validation = async {
        ensure!(
            catalog.schema_version
                == crate::studio::store::attachment::ATTACHMENT_CATALOG_SCHEMA_VERSION
                && catalog.thread_id == thread_id,
            "attachment catalog identity or schema mismatch"
        );
        for record in &mut catalog.records {
            ensure!(
                record.thread_id == thread_id,
                "attachment catalog record belongs to another Thread"
            );
            let recorded = PathBuf::from(&record.blob_relative_path);
            let relative = if recorded.is_absolute() {
                ensure!(
                    recorded.starts_with(&source_blobs),
                    "attachment {} is outside its Thread source blob root",
                    recorded.display()
                );
                let relative = recorded.strip_prefix(source_root).with_context(|| {
                    format!(
                        "attachment {} escaped its session source root",
                        recorded.display()
                    )
                })?;
                posix_relative(relative)?
            } else {
                posix_relative(&recorded)?
            };
            let relative_path = Path::new(&relative);
            ensure!(
                relative_path
                    .components()
                    .next()
                    .is_some_and(|component| component.as_os_str() == "blobs"),
                "attachment path must stay under the session blobs directory"
            );
            let host = target_root.join(relative_path);
            ensure!(
                host.starts_with(&target_blobs),
                "attachment {} is outside its Thread blob root",
                host.display()
            );
            pl_tool::workspace::path_safety::validate_existing_path_async(target_root, &host)
                .await
                .with_context(|| {
                    format!(
                        "attachment blob escaped the session root or followed a link: {}",
                        host.display()
                    )
                })?;
            let metadata = tokio::fs::symlink_metadata(&host)
                .await
                .with_context(|| format!("attachment blob is missing: {}", host.display()))?;
            ensure!(
                metadata.is_file()
                    && !pl_tool::workspace::path_safety::is_link_or_reparse(&metadata),
                "attachment blob is not a regular file: {}",
                host.display()
            );
            ensure!(
                metadata.len() == record.byte_size,
                "attachment blob length does not match its catalog record"
            );
            if record.blob_relative_path != relative {
                record.blob_relative_path = relative;
                changed = true;
            }
        }
        Ok::<(), anyhow::Error>(())
    }
    .await;
    validation.map_err(|error| {
        crate::toml_schema::migration_error(
            &path,
            "attachment-catalog",
            Some(catalog.schema_version),
            crate::studio::store::attachment::ATTACHMENT_CATALOG_SCHEMA_VERSION,
            "validate",
            error,
        )
    })?;
    if changed {
        crate::studio::store::attachment::write_migrated_attachment_catalog(&path, &catalog)
            .await?;
    }
    Ok(())
}

pub(crate) fn relative_blob_path(session: &SessionPaths, absolute: &Path) -> Result<String> {
    let blobs = session.blobs_dir();
    ensure!(
        absolute.starts_with(&blobs),
        "attachment {} is outside its Thread blob root",
        absolute.display()
    );
    let relative = absolute
        .strip_prefix(session.root())
        .with_context(|| format!("attachment {} escaped its session root", absolute.display()))?;
    posix_relative(relative)
}

async fn load_optional_journal(path: &Path) -> Result<Option<LayoutJournal>> {
    match tokio::fs::read_to_string(path).await {
        Ok(content) => Ok(Some(load_journal_from(&content, path)?)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.into()),
    }
}

fn load_journal_from(content: &str, path: &Path) -> Result<LayoutJournal> {
    let journal: LayoutJournal = toml::from_str(content)
        .with_context(|| format!("invalid session layout journal {}", path.display()))?;
    ensure!(
        journal.schema_version == LAYOUT_JOURNAL_SCHEMA_VERSION,
        "unsupported session layout journal schema"
    );
    let mut seen = BTreeSet::new();
    for item in &journal.moves {
        ensure!(
            seen.insert(item.thread_id.as_str()),
            "session layout journal repeats a Thread"
        );
    }
    Ok(journal)
}

async fn load_optional_marker(path: &Path) -> Result<Option<LayoutCompleteMarker>> {
    match tokio::fs::read_to_string(path).await {
        Ok(content) => Ok(Some(decode_marker(&content, path)?)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.into()),
    }
}

fn decode_marker(content: &str, path: &Path) -> Result<LayoutCompleteMarker> {
    let marker: LayoutCompleteMarker = toml::from_str(content)
        .with_context(|| format!("invalid session layout marker {}", path.display()))?;
    Ok(marker)
}

fn validate_complete_marker(marker: &LayoutCompleteMarker) -> Result<()> {
    ensure!(
        marker.schema_version == LAYOUT_JOURNAL_SCHEMA_VERSION,
        "unsupported session layout marker schema"
    );
    ensure!(marker.completed, "session layout marker is not complete");
    Ok(())
}

fn journal_is_complete(journal: &LayoutJournal) -> bool {
    journal.completed
        && journal
            .moves
            .iter()
            .all(|item| item.phase == LayoutMovePhase::Verified)
}

async fn validate_completed_journal(
    paths: &StudioPaths,
    catalog: &CatalogStore,
    workspaces: &WorkspaceStore,
    journal: &LayoutJournal,
) -> Result<()> {
    ensure!(
        journal_is_complete(journal),
        "session layout journal is not complete"
    );
    validate_journal_bindings(paths, catalog, workspaces, journal)?;
    for item in &journal.moves {
        ensure_verified_directories(paths, catalog, workspaces, item).await?;
    }
    Ok(())
}

fn validate_journal_bindings(
    paths: &StudioPaths,
    catalog: &CatalogStore,
    workspaces: &WorkspaceStore,
    journal: &LayoutJournal,
) -> Result<()> {
    ensure!(
        journal.schema_version == LAYOUT_JOURNAL_SCHEMA_VERSION,
        "unsupported session layout journal schema {}",
        journal.schema_version
    );
    for item in &journal.moves {
        validate_move_item(paths, catalog, workspaces, item)?;
    }
    Ok(())
}

fn validate_move_item(
    _paths: &StudioPaths,
    catalog: &CatalogStore,
    workspaces: &WorkspaceStore,
    item: &LayoutMove,
) -> Result<()> {
    let thread_key = storage_key(&item.thread_id, "Thread")?;
    let project_key = storage_key(&item.workspace_id, "Project")?;
    ensure!(
        is_storage_key(&item.source_key)
            && item.source_key == thread_key
            && item.target_thread_key == thread_key
            && item.target_project_key == project_key,
        "session layout journal keys do not match the catalog identities"
    );
    catalog_binding(catalog, workspaces, item)?;
    Ok(())
}

fn catalog_binding(
    catalog: &CatalogStore,
    workspaces: &WorkspaceStore,
    item: &LayoutMove,
) -> Result<crate::studio::catalog::CatalogEntry> {
    let entry = catalog
        .get(&item.thread_id)
        .context("layout move references a missing catalog Thread")?;
    ensure!(
        entry.workspace_id == item.workspace_id
            && entry.id == item.thread_id
            && workspaces.get(&item.workspace_id).is_some(),
        "layout move project identity drifted from catalog"
    );
    Ok(entry)
}

fn is_storage_key(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
}

async fn persist_journal(path: &Path, journal: &LayoutJournal) -> Result<()> {
    write_toml(path, journal).await
}

async fn persist_marker(path: &Path) -> Result<()> {
    write_toml(
        path,
        &LayoutCompleteMarker {
            schema_version: LAYOUT_JOURNAL_SCHEMA_VERSION,
            completed: true,
        },
    )
    .await
}

async fn write_toml<T: Serialize>(path: &Path, value: &T) -> Result<()> {
    let contents = toml::to_string_pretty(value)?.into_bytes();
    let path = path.to_path_buf();
    tokio::task::spawn_blocking(move || {
        pl_tool::workspace::write_file_atomically(&path, &contents)
    })
    .await??;
    Ok(())
}

async fn write_manifest_toml(path: &Path, contents: String) -> Result<()> {
    let path = path.to_path_buf();
    let contents = contents.into_bytes();
    tokio::task::spawn_blocking(move || {
        pl_tool::workspace::write_file_atomically(&path, &contents)
    })
    .await??;
    Ok(())
}

fn decode_project_manifest(path: &Path, content: &str) -> Result<ProjectManifest> {
    schema::decode_project(path, content)
}

fn decode_session_manifest(path: &Path, content: &str) -> Result<SessionManifest> {
    schema::decode_session(path, content)
}

fn expected_session_manifest(
    catalog: &CatalogStore,
    workspaces: &WorkspaceStore,
    item: &LayoutMove,
) -> Result<SessionManifest> {
    let entry = catalog_binding(catalog, workspaces, item)?;
    Ok(SessionManifest {
        schema_version: SESSION_MANIFEST_SCHEMA_VERSION,
        thread_id: entry.id.clone(),
        workspace_id: entry.workspace_id.clone(),
        parent_thread_id: entry.parent_thread_id.clone(),
        root_thread_id: entry.root_thread_id.clone(),
        workspace_mode: entry.workspace_mode,
        workspace_path: entry.workspace_path.clone(),
        created_at: entry.created_at,
    })
}

async fn persist_session_manifest_in(
    paths: &StudioPaths,
    directory: &Path,
    expected: &SessionManifest,
) -> Result<()> {
    ensure!(
        expected.schema_version == SESSION_MANIFEST_SCHEMA_VERSION,
        "unsupported session manifest schema"
    );
    let path = directory.join("session.toml");
    ensure_layout_write_path(paths, directory).await?;
    ensure_layout_write_path(paths, &path).await?;
    tokio::fs::create_dir_all(directory).await?;
    match tokio::fs::read_to_string(&path).await {
        Ok(content) => {
            let existing = decode_session_manifest(&path, &content)?;
            ensure_session_manifest_compatible(&path, &existing, expected)
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            write_manifest_toml(&path, schema::encode_session(expected)?).await
        }
        Err(error) => Err(error.into()),
    }
}

async fn load_matching_session_manifest(
    directory: &Path,
    expected: &SessionManifest,
) -> Result<SessionManifest> {
    let path = directory.join("session.toml");
    let content = tokio::fs::read_to_string(&path).await.with_context(|| {
        format!(
            "session layout target has no ownership proof {}",
            path.display()
        )
    })?;
    let existing = decode_session_manifest(&path, &content)?;
    ensure_session_manifest_compatible(&path, &existing, expected)?;
    Ok(existing)
}

async fn path_exists_including_links(path: &Path) -> Result<bool> {
    match tokio::fs::symlink_metadata(path).await {
        Ok(_) => Ok(true),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error.into()),
    }
}

async fn ensure_absent_source(source: &Path) -> Result<()> {
    match tokio::fs::symlink_metadata(source).await {
        Ok(metadata) => anyhow::bail!(
            "session layout source still exists after the move{}: {}",
            if pl_tool::workspace::path_safety::is_link_or_reparse(&metadata) {
                " as a link"
            } else {
                ""
            },
            source.display()
        ),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.into()),
    }
}

async fn ensure_safe_session_directory(paths: &StudioPaths, directory: &Path) -> Result<()> {
    ensure_layout_write_path(paths, directory).await?;
    let metadata = tokio::fs::symlink_metadata(directory)
        .await
        .with_context(|| format!("session layout target is missing: {}", directory.display()))?;
    ensure!(
        metadata.is_dir() && !pl_tool::workspace::path_safety::is_link_or_reparse(&metadata),
        "session layout target is not a safe directory: {}",
        directory.display()
    );
    Ok(())
}

async fn ensure_verified_directories(
    paths: &StudioPaths,
    catalog: &CatalogStore,
    workspaces: &WorkspaceStore,
    item: &LayoutMove,
) -> Result<()> {
    let source = paths.legacy_sessions_dir().join(&item.source_key);
    let target = paths.session_paths(&item.workspace_id, &item.thread_id)?;
    ensure_absent_source(&source).await?;
    ensure_safe_session_directory(paths, target.root()).await?;
    load_matching_session_manifest(
        target.root(),
        &expected_session_manifest(catalog, workspaces, item)?,
    )
    .await?;
    Ok(())
}

async fn ensure_layout_write_path(paths: &StudioPaths, candidate: &Path) -> Result<()> {
    pl_tool::workspace::path_safety::validate_path_for_write_async(paths.home(), candidate)
        .await
        .with_context(|| {
            format!(
                "session layout path escaped the Studio home or followed a link: {}",
                candidate.display()
            )
        })
}

fn layout_error(error: impl Into<anyhow::Error>) -> anyhow::Error {
    let error = error.into();
    if error.is::<SessionLayoutMigrationFailed>() {
        error
    } else {
        SessionLayoutMigrationFailed { source: error }.into()
    }
}

#[cfg(test)]
pub(crate) fn is_layout_error(error: &anyhow::Error) -> bool {
    error.is::<SessionLayoutMigrationFailed>()
        || error
            .chain()
            .any(|cause| cause.is::<SessionLayoutMigrationFailed>())
}

/// Detects whether a layout journal or project tree already exists on disk.
#[cfg(test)]
pub(crate) fn layout_evidence(paths: &StudioPaths) -> [PathBuf; 4] {
    [
        paths.projects_dir(),
        paths.legacy_sessions_dir(),
        paths.migrations_dir().join(LAYOUT_JOURNAL_FILE_NAME),
        paths.migrations_dir().join(LAYOUT_MARKER_FILE_NAME),
    ]
}

#[cfg(test)]
mod layout_migration_tests {
    use super::*;
    use crate::studio::store::directory::{DirectoryDelta, ProjectDirectoryRecord};

    async fn seed_catalog(
        store: &StudioStore,
        workspace_id: &str,
        thread_id: &str,
        ssh_alias: Option<&str>,
    ) -> Result<()> {
        let mut delta = DirectoryDelta::upsert_project(ProjectDirectoryRecord {
            id: workspace_id.into(),
            kind: pl_protocol::studio::WorkspaceKind::Project,
            name: "Layout".into(),
            path: "/tmp/layout".into(),
            ssh_alias: ssh_alias.map(str::to_owned),
            created_at: 1,
            updated_at: 1,
            last_opened_at: None,
            closed: false,
        });
        let (thread_delta, _) = DirectoryDelta::register_root_thread(
            thread_id.into(),
            workspace_id,
            "layout",
            pl_protocol::ThreadModeId::simple(),
            pl_protocol::ThreadWorkspaceMode::Local,
            "/tmp/layout".into(),
        );
        delta.thread_upserts = thread_delta.thread_upserts;
        store.persist_directory_summaries(&delta).await
    }

    async fn reset_layout_for_legacy(
        paths: &StudioPaths,
        workspace_id: &str,
        thread_id: &str,
    ) -> Result<()> {
        let session = paths.session_paths(workspace_id, thread_id)?;
        if tokio::fs::try_exists(session.root()).await? {
            tokio::fs::remove_dir_all(session.root()).await?;
        }
        for name in [LAYOUT_JOURNAL_FILE_NAME, LAYOUT_MARKER_FILE_NAME] {
            match tokio::fs::remove_file(paths.migrations_dir().join(name)).await {
                Ok(()) => {}
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(error) => return Err(error.into()),
            }
        }
        Ok(())
    }

    async fn write_legacy_session(
        paths: &StudioPaths,
        thread_id: &str,
        payload: &[u8],
    ) -> Result<PathBuf> {
        let dir = paths.legacy_thread_dir(thread_id)?;
        tokio::fs::create_dir_all(&dir).await?;
        for (name, bytes) in [
            ("history.sqlite", payload),
            ("history.sqlite-wal", b"wal-bytes".as_slice()),
            ("history.sqlite-shm", b"shm-bytes".as_slice()),
            ("unknown.bin", b"keep-me".as_slice()),
        ] {
            tokio::fs::write(dir.join(name), bytes).await?;
        }
        let blobs = dir.join("blobs/aa");
        tokio::fs::create_dir_all(&blobs).await?;
        tokio::fs::write(blobs.join("blob"), b"blob-bytes").await?;
        // The old production writer derived absolute blob paths from its canonical Store home.
        let storage_path = tokio::fs::canonicalize(blobs.join("blob")).await?;
        let catalog = toml::to_string(&crate::studio::store::attachment::AttachmentCatalog {
            schema_version: 1,
            thread_id: thread_id.to_owned(),
            records: vec![crate::studio::AttachmentRecord {
                id: "att-1".into(),
                thread_id: thread_id.to_owned(),
                modality: pl_protocol::studio::StudioAttachmentModality::File,
                media_type: "text/plain".into(),
                filename: None,
                blob_relative_path: storage_path.to_string_lossy().into_owned(),
                byte_size: 10,
                content_sha256: "aa".into(),
                width: None,
                height: None,
                created_at: 1,
            }],
        })?;
        tokio::fs::write(dir.join("attachments.toml"), catalog).await?;
        Ok(dir)
    }

    #[tokio::test]
    async fn migrates_flat_sessions_with_sidecars_and_relative_attachments() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        seed_catalog(&store, "project-a", "thread-a", None).await?;
        drop(store);
        reset_layout_for_legacy(&paths, "project-a", "thread-a").await?;
        let source = write_legacy_session(&paths, "thread-a", b"history-bytes").await?;
        let store = StudioStore::open(paths.database()).await?;
        let session = store.session_paths("project-a", "thread-a")?;
        assert!(!tokio::fs::try_exists(&source).await?);
        assert_eq!(
            tokio::fs::read(session.history_database()).await?,
            b"history-bytes"
        );
        {
            let mut wal = session.history_database().into_os_string();
            wal.push("-wal");
            assert_eq!(tokio::fs::read(wal).await?, b"wal-bytes");
        }
        assert_eq!(
            tokio::fs::read(session.root().join("unknown.bin")).await?,
            b"keep-me"
        );
        let attachments = store.list_thread_attachments("thread-a").await?;
        assert_eq!(attachments.len(), 1);
        assert_eq!(
            store.read_attachment_bytes("thread-a", "att-1").await?,
            b"blob-bytes"
        );
        let persisted = tokio::fs::read_to_string(session.attachments_catalog()).await?;
        assert!(!persisted.contains(session.blobs_dir().to_string_lossy().as_ref()));
        assert!(persisted.contains("blobs/aa/blob"));
        drop(store);
        let reopened = StudioStore::open(paths.database()).await?;
        assert_eq!(
            tokio::fs::read(session.history_database()).await?,
            b"history-bytes"
        );
        drop(reopened);
        Ok(())
    }

    #[tokio::test]
    async fn isolates_same_path_projects_by_stable_id() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        seed_catalog(&store, "local-project", "thread-local", None).await?;
        seed_catalog(&store, "ssh-project", "thread-ssh", Some("jump")).await?;
        let local = store.session_paths("local-project", "thread-local")?;
        let ssh = store.session_paths("ssh-project", "thread-ssh")?;
        assert_ne!(local.root(), ssh.root());
        assert_eq!(local.workspace_id(), "local-project");
        assert_eq!(ssh.scratch_dir(), ssh.root().join("scratch"));
        let _ = store.session_scratch_dir_for("local-project", "thread-local")?;
        assert_ne!(
            crate::studio::paths::storage_key("local-project", "Project")?,
            crate::studio::paths::storage_key("ssh-project", "Project")?
        );
        Ok(())
    }

    #[tokio::test]
    async fn target_conflict_does_not_merge_or_reset() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        seed_catalog(&store, "project-a", "thread-a", None).await?;
        drop(store);
        reset_layout_for_legacy(&paths, "project-a", "thread-a").await?;
        let source = write_legacy_session(&paths, "thread-a", b"source-bytes").await?;
        let session = paths.session_paths("project-a", "thread-a")?;
        tokio::fs::create_dir_all(session.root()).await?;
        tokio::fs::write(session.history_database(), b"existing-target").await?;
        let error = StudioStore::open(paths.database())
            .await
            .err()
            .expect("conflict must fail");
        assert!(is_layout_error(&error), "{error:#}");
        assert!(layout_evidence(&paths).iter().any(|path| path.exists()));
        assert_eq!(
            tokio::fs::read(source.join("history.sqlite")).await?,
            b"source-bytes"
        );
        assert_eq!(
            tokio::fs::read(session.history_database()).await?,
            b"existing-target"
        );
        assert!(!temp.path().join("startup-backups").exists());
        Ok(())
    }

    fn expected_layout_manifest(store: &StudioStore, thread_id: &str) -> Result<SessionManifest> {
        let entry = store
            .catalog()
            .get(thread_id)
            .ok_or_else(|| anyhow::anyhow!("missing catalog thread"))?;
        Ok(SessionManifest {
            schema_version: SESSION_MANIFEST_SCHEMA_VERSION,
            thread_id: entry.id,
            workspace_id: entry.workspace_id,
            parent_thread_id: entry.parent_thread_id,
            root_thread_id: entry.root_thread_id,
            workspace_mode: entry.workspace_mode,
            workspace_path: entry.workspace_path,
            created_at: entry.created_at,
        })
    }

    #[tokio::test]
    async fn resumes_after_rename_before_journal_update() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        seed_catalog(&store, "project-a", "thread-a", None).await?;
        let proof = expected_layout_manifest(&store, "thread-a")?;
        drop(store);
        reset_layout_for_legacy(&paths, "project-a", "thread-a").await?;
        let source = write_legacy_session(&paths, "thread-a", b"moved-bytes").await?;
        persist_session_manifest_in(&paths, &source, &proof).await?;
        let session = paths.session_paths("project-a", "thread-a")?;
        tokio::fs::create_dir_all(session.root().parent().expect("parent")).await?;
        pl_tool::workspace::move_owned_path(&source, session.root())?;
        let journal = LayoutJournal {
            schema_version: LAYOUT_JOURNAL_SCHEMA_VERSION,
            completed: false,
            orphans: Vec::new(),
            moves: vec![LayoutMove {
                thread_id: "thread-a".into(),
                workspace_id: "project-a".into(),
                source_key: crate::studio::paths::thread_storage_key("thread-a")?,
                target_project_key: crate::studio::paths::storage_key("project-a", "Project")?,
                target_thread_key: crate::studio::paths::thread_storage_key("thread-a")?,
                phase: LayoutMovePhase::Planned,
            }],
        };
        tokio::fs::create_dir_all(paths.migrations_dir()).await?;
        persist_journal(
            &paths.migrations_dir().join(LAYOUT_JOURNAL_FILE_NAME),
            &journal,
        )
        .await?;
        let store = StudioStore::open(paths.database()).await?;
        assert_eq!(
            tokio::fs::read(session.history_database()).await?,
            b"moved-bytes"
        );
        assert!(!tokio::fs::try_exists(&source).await?);
        drop(store);
        Ok(())
    }

    #[tokio::test]
    async fn unknown_manifest_version_fails_closed() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        seed_catalog(&store, "project-a", "thread-a", None).await?;
        let session = store.session_paths("project-a", "thread-a")?;
        tokio::fs::write(
            session.session_manifest(),
            "schemaVersion = 99\nthreadId = \"thread-a\"\nworkspaceId = \"other\"\nrootThreadId = \"thread-a\"\nworkspaceMode = \"local\"\nworkspacePath = \"/tmp/layout\"\ncreatedAt = 1\n",
        )
        .await?;
        let error = store
            .prepare_session_manifest(&store.catalog().get("thread-a").unwrap().to_thread())
            .await
            .expect_err("future manifest must fail");
        assert!(error.chain().any(|cause| {
            cause
                .downcast_ref::<crate::toml_schema::DocumentMigrationFailed>()
                .is_some()
        }));
        Ok(())
    }

    #[tokio::test]
    async fn unregistered_legacy_directory_stays_in_place() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let _store = StudioStore::open(paths.database()).await?;
        drop(_store);
        let orphan = paths.legacy_sessions_dir().join("not-a-catalog-key");
        tokio::fs::create_dir_all(&orphan).await?;
        tokio::fs::write(orphan.join("history.sqlite"), b"orphan").await?;
        let _store = StudioStore::open(paths.database()).await?;
        assert_eq!(
            tokio::fs::read(orphan.join("history.sqlite")).await?,
            b"orphan"
        );
        Ok(())
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn symlink_session_source_fails_without_following() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        seed_catalog(&store, "project-a", "thread-a", None).await?;
        drop(store);
        reset_layout_for_legacy(&paths, "project-a", "thread-a").await?;
        let real = temp.path().join("outside");
        tokio::fs::create_dir_all(&real).await?;
        tokio::fs::write(real.join("secret"), b"do-not-follow").await?;
        tokio::fs::create_dir_all(paths.legacy_sessions_dir()).await?;
        std::os::unix::fs::symlink(&real, paths.legacy_thread_dir("thread-a")?)?;
        let error = match StudioStore::open(paths.database()).await {
            Ok(_) => anyhow::bail!("symlink session source must fail"),
            Err(error) => error,
        };
        assert!(is_layout_error(&error));
        assert_eq!(
            tokio::fs::read(real.join("secret")).await?,
            b"do-not-follow"
        );
        Ok(())
    }

    #[tokio::test]
    async fn foreign_absolute_attachment_is_rejected() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        seed_catalog(&store, "project-a", "thread-a", None).await?;
        seed_catalog(&store, "project-b", "thread-b", None).await?;
        drop(store);
        reset_layout_for_legacy(&paths, "project-a", "thread-a").await?;
        reset_layout_for_legacy(&paths, "project-b", "thread-b").await?;
        let source = write_legacy_session(&paths, "thread-a", b"history-bytes").await?;
        let other = write_legacy_session(&paths, "thread-b", b"other-bytes").await?;
        let foreign = tokio::fs::canonicalize(other.join("blobs/aa/blob")).await?;
        let catalog = toml::to_string(&crate::studio::store::attachment::AttachmentCatalog {
            schema_version: 1,
            thread_id: "thread-a".into(),
            records: vec![crate::studio::AttachmentRecord {
                id: "att-1".into(),
                thread_id: "thread-a".into(),
                modality: pl_protocol::studio::StudioAttachmentModality::File,
                media_type: "text/plain".into(),
                filename: None,
                blob_relative_path: foreign.to_string_lossy().into_owned(),
                byte_size: 10,
                content_sha256: "aa".into(),
                width: None,
                height: None,
                created_at: 1,
            }],
        })?;
        tokio::fs::write(source.join("attachments.toml"), catalog).await?;
        let error = match StudioStore::open(paths.database()).await {
            Ok(_) => anyhow::bail!("foreign attachment must fail"),
            Err(error) => error,
        };
        assert!(is_layout_error(&error));
        assert!(error.chain().any(|cause| {
            cause
                .downcast_ref::<crate::toml_schema::DocumentMigrationFailed>()
                .is_some()
        }));
        let session = paths.session_paths("project-a", "thread-a")?;
        assert_eq!(
            tokio::fs::read(session.history_database()).await?,
            b"history-bytes"
        );
        assert!(
            !paths
                .migrations_dir()
                .join(LAYOUT_MARKER_FILE_NAME)
                .exists()
        );
        Ok(())
    }

    #[tokio::test]
    async fn missing_attachment_blob_fails_before_completion() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        seed_catalog(&store, "project-a", "thread-a", None).await?;
        drop(store);
        reset_layout_for_legacy(&paths, "project-a", "thread-a").await?;
        let source = write_legacy_session(&paths, "thread-a", b"history-bytes").await?;
        tokio::fs::remove_file(source.join("blobs/aa/blob")).await?;
        let error = match StudioStore::open(paths.database()).await {
            Ok(_) => anyhow::bail!("missing blob must fail"),
            Err(error) => error,
        };
        assert!(is_layout_error(&error));
        assert!(error.chain().any(|cause| {
            cause
                .downcast_ref::<crate::toml_schema::DocumentMigrationFailed>()
                .is_some()
        }));
        assert!(
            !paths
                .migrations_dir()
                .join(LAYOUT_MARKER_FILE_NAME)
                .exists()
        );
        Ok(())
    }

    #[tokio::test]
    async fn edited_journal_key_does_not_move_source() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        seed_catalog(&store, "project-a", "thread-a", None).await?;
        drop(store);
        reset_layout_for_legacy(&paths, "project-a", "thread-a").await?;
        let source = write_legacy_session(&paths, "thread-a", b"history-bytes").await?;
        let journal = LayoutJournal {
            schema_version: LAYOUT_JOURNAL_SCHEMA_VERSION,
            completed: false,
            orphans: Vec::new(),
            moves: vec![LayoutMove {
                thread_id: "thread-a".into(),
                workspace_id: "project-a".into(),
                source_key: "../escape".into(),
                target_project_key: crate::studio::paths::storage_key("project-a", "Project")?,
                target_thread_key: crate::studio::paths::thread_storage_key("thread-a")?,
                phase: LayoutMovePhase::Planned,
            }],
        };
        tokio::fs::create_dir_all(paths.migrations_dir()).await?;
        persist_journal(
            &paths.migrations_dir().join(LAYOUT_JOURNAL_FILE_NAME),
            &journal,
        )
        .await?;
        let error = match StudioStore::open(paths.database()).await {
            Ok(_) => anyhow::bail!("edited journal must fail"),
            Err(error) => error,
        };
        assert!(is_layout_error(&error));
        assert_eq!(
            tokio::fs::read(source.join("history.sqlite")).await?,
            b"history-bytes"
        );
        Ok(())
    }

    #[tokio::test]
    async fn marker_without_journal_fails_closed() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let _store = StudioStore::open(paths.database()).await?;
        drop(_store);
        tokio::fs::create_dir_all(paths.migrations_dir()).await?;
        match tokio::fs::remove_file(paths.migrations_dir().join(LAYOUT_JOURNAL_FILE_NAME)).await {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
        tokio::fs::write(
            paths.migrations_dir().join(LAYOUT_MARKER_FILE_NAME),
            "schemaVersion = 1\ncompleted = true\n",
        )
        .await?;
        let error = match StudioStore::open(paths.database()).await {
            Ok(_) => anyhow::bail!("marker without journal must fail"),
            Err(error) => error,
        };
        assert!(is_layout_error(&error));
        Ok(())
    }

    #[tokio::test]
    async fn complete_journal_without_marker_is_republished() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        seed_catalog(&store, "project-a", "thread-a", None).await?;
        drop(store);
        reset_layout_for_legacy(&paths, "project-a", "thread-a").await?;
        write_legacy_session(&paths, "thread-a", b"history-bytes").await?;
        let store = StudioStore::open(paths.database()).await?;
        drop(store);
        tokio::fs::remove_file(paths.migrations_dir().join(LAYOUT_MARKER_FILE_NAME)).await?;
        let store = StudioStore::open(paths.database()).await?;
        assert!(tokio::fs::try_exists(paths.migrations_dir().join(LAYOUT_MARKER_FILE_NAME)).await?);
        drop(store);
        Ok(())
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn symlink_target_ancestor_is_rejected_before_create() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        seed_catalog(&store, "project-a", "thread-a", None).await?;
        drop(store);
        reset_layout_for_legacy(&paths, "project-a", "thread-a").await?;
        let source = write_legacy_session(&paths, "thread-a", b"history-bytes").await?;
        let outside = temp.path().join("outside-projects");
        tokio::fs::create_dir_all(&outside).await?;
        tokio::fs::write(outside.join("sentinel"), b"keep").await?;
        let projects = paths.projects_dir();
        if tokio::fs::try_exists(&projects).await? {
            tokio::fs::remove_dir_all(&projects).await?;
        }
        std::os::unix::fs::symlink(&outside, &projects)?;
        let error = match StudioStore::open(paths.database()).await {
            Ok(_) => anyhow::bail!("symlink ancestor must fail"),
            Err(error) => error,
        };
        assert!(is_layout_error(&error));
        assert_eq!(tokio::fs::read(outside.join("sentinel")).await?, b"keep");
        assert_eq!(
            tokio::fs::read(source.join("history.sqlite")).await?,
            b"history-bytes"
        );
        Ok(())
    }

    #[tokio::test]
    async fn fake_verified_journal_with_source_present_fails_closed() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        seed_catalog(&store, "project-a", "thread-a", None).await?;
        drop(store);
        reset_layout_for_legacy(&paths, "project-a", "thread-a").await?;
        let source = write_legacy_session(&paths, "thread-a", b"still-here").await?;
        let journal = LayoutJournal {
            schema_version: LAYOUT_JOURNAL_SCHEMA_VERSION,
            completed: true,
            orphans: Vec::new(),
            moves: vec![LayoutMove {
                thread_id: "thread-a".into(),
                workspace_id: "project-a".into(),
                source_key: crate::studio::paths::thread_storage_key("thread-a")?,
                target_project_key: crate::studio::paths::storage_key("project-a", "Project")?,
                target_thread_key: crate::studio::paths::thread_storage_key("thread-a")?,
                phase: LayoutMovePhase::Verified,
            }],
        };
        tokio::fs::create_dir_all(paths.migrations_dir()).await?;
        persist_journal(
            &paths.migrations_dir().join(LAYOUT_JOURNAL_FILE_NAME),
            &journal,
        )
        .await?;
        tokio::fs::write(
            paths.migrations_dir().join(LAYOUT_MARKER_FILE_NAME),
            "schemaVersion = 1\ncompleted = true\n",
        )
        .await?;
        let error = match StudioStore::open(paths.database()).await {
            Ok(_) => anyhow::bail!("fake verified source must fail"),
            Err(error) => error,
        };
        assert!(is_layout_error(&error), "{error:#}");
        assert_eq!(
            tokio::fs::read(source.join("history.sqlite")).await?,
            b"still-here"
        );
        Ok(())
    }

    #[tokio::test]
    async fn complete_journal_with_missing_target_fails_closed() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        seed_catalog(&store, "project-a", "thread-a", None).await?;
        let proof = expected_layout_manifest(&store, "thread-a")?;
        drop(store);
        reset_layout_for_legacy(&paths, "project-a", "thread-a").await?;
        let source = write_legacy_session(&paths, "thread-a", b"history-bytes").await?;
        persist_session_manifest_in(&paths, &source, &proof).await?;
        let session = paths.session_paths("project-a", "thread-a")?;
        tokio::fs::create_dir_all(session.root().parent().expect("parent")).await?;
        pl_tool::workspace::move_owned_path(&source, session.root())?;
        let journal = LayoutJournal {
            schema_version: LAYOUT_JOURNAL_SCHEMA_VERSION,
            completed: true,
            orphans: Vec::new(),
            moves: vec![LayoutMove {
                thread_id: "thread-a".into(),
                workspace_id: "project-a".into(),
                source_key: crate::studio::paths::thread_storage_key("thread-a")?,
                target_project_key: crate::studio::paths::storage_key("project-a", "Project")?,
                target_thread_key: crate::studio::paths::thread_storage_key("thread-a")?,
                phase: LayoutMovePhase::Verified,
            }],
        };
        tokio::fs::create_dir_all(paths.migrations_dir()).await?;
        persist_journal(
            &paths.migrations_dir().join(LAYOUT_JOURNAL_FILE_NAME),
            &journal,
        )
        .await?;
        tokio::fs::write(
            paths.migrations_dir().join(LAYOUT_MARKER_FILE_NAME),
            "schemaVersion = 1\ncompleted = true\n",
        )
        .await?;
        tokio::fs::remove_dir_all(session.root()).await?;
        let error = match StudioStore::open(paths.database()).await {
            Ok(_) => anyhow::bail!("missing target must fail"),
            Err(error) => error,
        };
        assert!(is_layout_error(&error), "{error:#}");
        assert!(
            tokio::fs::try_exists(paths.migrations_dir().join(LAYOUT_MARKER_FILE_NAME)).await?,
            "complete marker must remain so a later successful run cannot pretend this completed"
        );
        assert!(!tokio::fs::try_exists(session.root()).await?);
        Ok(())
    }

    #[tokio::test]
    async fn unproven_target_is_not_taken_over() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        seed_catalog(&store, "project-a", "thread-a", None).await?;
        drop(store);
        reset_layout_for_legacy(&paths, "project-a", "thread-a").await?;
        let session = paths.session_paths("project-a", "thread-a")?;
        tokio::fs::create_dir_all(session.root()).await?;
        tokio::fs::write(session.history_database(), b"foreign-target").await?;
        let journal = LayoutJournal {
            schema_version: LAYOUT_JOURNAL_SCHEMA_VERSION,
            completed: false,
            orphans: Vec::new(),
            moves: vec![LayoutMove {
                thread_id: "thread-a".into(),
                workspace_id: "project-a".into(),
                source_key: crate::studio::paths::thread_storage_key("thread-a")?,
                target_project_key: crate::studio::paths::storage_key("project-a", "Project")?,
                target_thread_key: crate::studio::paths::thread_storage_key("thread-a")?,
                phase: LayoutMovePhase::Planned,
            }],
        };
        tokio::fs::create_dir_all(paths.migrations_dir()).await?;
        persist_journal(
            &paths.migrations_dir().join(LAYOUT_JOURNAL_FILE_NAME),
            &journal,
        )
        .await?;
        let error = match StudioStore::open(paths.database()).await {
            Ok(_) => anyhow::bail!("unproven target must fail"),
            Err(error) => error,
        };
        assert!(is_layout_error(&error), "{error:#}");
        assert_eq!(
            tokio::fs::read(session.history_database()).await?,
            b"foreign-target"
        );
        assert!(!session.session_manifest().exists());
        Ok(())
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn linked_blob_parent_is_rejected() -> Result<()> {
        for kind in ["blobs-dir", "shard-dir", "catalog-file"] {
            let temp = tempfile::tempdir()?;
            let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
            let store = StudioStore::open(paths.database()).await?;
            seed_catalog(&store, "project-a", "thread-a", None).await?;
            drop(store);
            reset_layout_for_legacy(&paths, "project-a", "thread-a").await?;
            let source = write_legacy_session(&paths, "thread-a", b"history-bytes").await?;
            let outside = temp.path().join(format!("external-{kind}"));
            tokio::fs::create_dir_all(&outside).await?;
            tokio::fs::write(outside.join("sentinel"), b"external-bytes").await?;
            match kind {
                "blobs-dir" => {
                    tokio::fs::remove_dir_all(source.join("blobs")).await?;
                    tokio::fs::create_dir_all(outside.join("aa")).await?;
                    tokio::fs::write(outside.join("aa/blob"), b"external-bytes").await?;
                    std::os::unix::fs::symlink(&outside, source.join("blobs"))?;
                }
                "shard-dir" => {
                    tokio::fs::remove_dir_all(source.join("blobs/aa")).await?;
                    tokio::fs::create_dir_all(outside.join("aa")).await?;
                    tokio::fs::write(outside.join("aa/blob"), b"external-bytes").await?;
                    std::os::unix::fs::symlink(outside.join("aa"), source.join("blobs/aa"))?;
                }
                "catalog-file" => {
                    let real = outside.join("attachments.toml");
                    tokio::fs::copy(source.join("attachments.toml"), &real).await?;
                    tokio::fs::remove_file(source.join("attachments.toml")).await?;
                    std::os::unix::fs::symlink(&real, source.join("attachments.toml"))?;
                }
                _ => unreachable!(),
            }
            let error = match StudioStore::open(paths.database()).await {
                Ok(_) => anyhow::bail!("{kind} link must fail"),
                Err(error) => error,
            };
            assert!(is_layout_error(&error), "{kind}: {error:#}");
            assert!(
                !paths
                    .migrations_dir()
                    .join(LAYOUT_MARKER_FILE_NAME)
                    .exists()
            );
            assert_eq!(
                tokio::fs::read(outside.join("sentinel")).await?,
                b"external-bytes"
            );
        }
        Ok(())
    }

    #[tokio::test]
    async fn moved_target_without_proof_is_rejected() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let paths = StudioPaths::resolve(Some(temp.path().to_path_buf()))?;
        let store = StudioStore::open(paths.database()).await?;
        seed_catalog(&store, "project-a", "thread-a", None).await?;
        drop(store);
        reset_layout_for_legacy(&paths, "project-a", "thread-a").await?;
        let source = write_legacy_session(&paths, "thread-a", b"history-bytes").await?;
        let session = paths.session_paths("project-a", "thread-a")?;
        tokio::fs::create_dir_all(session.root().parent().expect("parent")).await?;
        pl_tool::workspace::move_owned_path(&source, session.root())?;
        let journal = LayoutJournal {
            schema_version: LAYOUT_JOURNAL_SCHEMA_VERSION,
            completed: false,
            orphans: Vec::new(),
            moves: vec![LayoutMove {
                thread_id: "thread-a".into(),
                workspace_id: "project-a".into(),
                source_key: crate::studio::paths::thread_storage_key("thread-a")?,
                target_project_key: crate::studio::paths::storage_key("project-a", "Project")?,
                target_thread_key: crate::studio::paths::thread_storage_key("thread-a")?,
                phase: LayoutMovePhase::Moved,
            }],
        };
        tokio::fs::create_dir_all(paths.migrations_dir()).await?;
        persist_journal(
            &paths.migrations_dir().join(LAYOUT_JOURNAL_FILE_NAME),
            &journal,
        )
        .await?;
        let error = match StudioStore::open(paths.database()).await {
            Ok(_) => anyhow::bail!("moved without proof must fail"),
            Err(error) => error,
        };
        assert!(is_layout_error(&error), "{error:#}");
        assert_eq!(
            tokio::fs::read(session.history_database()).await?,
            b"history-bytes"
        );
        assert!(!session.session_manifest().exists());
        Ok(())
    }
}

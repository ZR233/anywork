//! Frozen v2 manifests and their explicit version-migrate ownership conversion.
use super::{SessionManifest, WorkspaceManifest};
use anyhow::Result;
use serde::{Deserialize, Serialize};
use version_migrate::{IntoDomain, MigratesTo, Migrator, Versioned};

const KEY: &str = "schemaVersion";
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
enum WorkspaceModeV1 {
    Local,
    Worktree,
}
impl From<WorkspaceModeV1> for pl_protocol::ThreadWorkspaceMode {
    fn from(value: WorkspaceModeV1) -> Self {
        match value {
            WorkspaceModeV1::Local => Self::Local,
            WorkspaceModeV1::Worktree => Self::Worktree,
        }
    }
}
#[derive(Debug, Serialize, Deserialize, Versioned)]
#[versioned(version = "1.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ProjectManifestV1 {
    project_id: String,
    path: String,
    ssh_alias: Option<String>,
}
#[derive(Debug, Serialize, Deserialize, Versioned)]
#[versioned(version = "1.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SessionManifestV1 {
    thread_id: String,
    project_id: String,
    parent_thread_id: Option<String>,
    root_thread_id: String,
    workspace_mode: WorkspaceModeV1,
    workspace_path: String,
    created_at: i64,
}
#[derive(Debug, Serialize, Deserialize, Versioned)]
#[versioned(version = "2.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct WorkspaceV2 {
    workspace_id: String,
    kind: pl_protocol::studio::WorkspaceKind,
    path: String,
    ssh_alias: Option<String>,
}
#[derive(Debug, Serialize, Deserialize, Versioned)]
#[versioned(version = "2.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SessionV2 {
    thread_id: String,
    workspace_id: String,
    parent_thread_id: Option<String>,
    root_thread_id: String,
    workspace_mode: pl_protocol::ThreadWorkspaceMode,
    workspace_path: String,
    created_at: i64,
}
impl MigratesTo<WorkspaceV2> for ProjectManifestV1 {
    fn migrate(self) -> WorkspaceV2 {
        WorkspaceV2 {
            workspace_id: self.project_id,
            kind: pl_protocol::studio::WorkspaceKind::Project,
            path: self.path,
            ssh_alias: self.ssh_alias,
        }
    }
}
impl MigratesTo<SessionV2> for SessionManifestV1 {
    fn migrate(self) -> SessionV2 {
        SessionV2 {
            thread_id: self.thread_id,
            workspace_id: self.project_id,
            parent_thread_id: self.parent_thread_id,
            root_thread_id: self.root_thread_id,
            workspace_mode: self.workspace_mode.into(),
            workspace_path: self.workspace_path,
            created_at: self.created_at,
        }
    }
}
impl IntoDomain<WorkspaceV2> for WorkspaceV2 {
    fn into_domain(self) -> Self {
        self
    }
}
impl IntoDomain<SessionV2> for SessionV2 {
    fn into_domain(self) -> Self {
        self
    }
}
fn workspace_migrator() -> Result<Migrator> {
    let mut migrator = Migrator::new();
    migrator
        .register(
            Migrator::define("workspace-manifest")
                .with_keys(KEY, "data")
                .from::<ProjectManifestV1>()
                .step::<WorkspaceV2>()
                .into::<WorkspaceV2>(),
        )
        .map_err(|error| crate::toml_schema::chain_error("workspace-manifest", error))?;
    Ok(migrator)
}
fn session_migrator() -> Result<Migrator> {
    let mut migrator = Migrator::new();
    migrator
        .register(
            Migrator::define("session-manifest")
                .with_keys(KEY, "data")
                .from::<SessionManifestV1>()
                .step::<SessionV2>()
                .into::<SessionV2>(),
        )
        .map_err(|error| crate::toml_schema::chain_error("session-manifest", error))?;
    Ok(migrator)
}
pub(crate) fn decode_v2_workspace(
    path: &std::path::Path,
    content: &str,
) -> Result<WorkspaceManifest> {
    let doc = crate::toml_schema::load::<ProjectManifestV1, WorkspaceV2>(
        path,
        content,
        &workspace_migrator()?,
        "workspace-manifest",
        KEY,
    )?
    .document;
    Ok(WorkspaceManifest {
        schema_version: 2,
        workspace_id: doc.workspace_id,
        kind: doc.kind,
        path: doc.path,
        ssh_alias: doc.ssh_alias,
    })
}
pub(crate) fn decode_v2_session(path: &std::path::Path, content: &str) -> Result<SessionManifest> {
    let doc = crate::toml_schema::load::<SessionManifestV1, SessionV2>(
        path,
        content,
        &session_migrator()?,
        "session-manifest",
        KEY,
    )?
    .document;
    Ok(SessionManifest {
        schema_version: 2,
        workspace_id: doc.workspace_id,
        thread_id: doc.thread_id,
        parent_thread_id: doc.parent_thread_id,
        root_thread_id: doc.root_thread_id,
        workspace_mode: doc.workspace_mode,
        workspace_path: doc.workspace_path,
        created_at: doc.created_at,
    })
}
pub(super) fn encode_workspace(document: &WorkspaceManifest) -> Result<String> {
    crate::toml_schema::encode(
        &WorkspaceV2 {
            workspace_id: document.workspace_id.clone(),
            kind: document.kind,
            path: document.path.clone(),
            ssh_alias: document.ssh_alias.clone(),
        },
        KEY,
    )
}
pub(super) fn encode_session(document: &SessionManifest) -> Result<String> {
    crate::toml_schema::encode(
        &SessionV2 {
            workspace_id: document.workspace_id.clone(),
            thread_id: document.thread_id.clone(),
            parent_thread_id: document.parent_thread_id.clone(),
            root_thread_id: document.root_thread_id.clone(),
            workspace_mode: document.workspace_mode,
            workspace_path: document.workspace_path.clone(),
            created_at: document.created_at,
        },
        KEY,
    )
}

//! Current Workspace/Thread identity manifests. Legacy formats are decoded only by layout migration.
use std::path::Path;

use anyhow::{Context, Result, ensure};
use pl_protocol::{ThreadWorkspaceMode, studio::WorkspaceKind};
use serde::{Deserialize, Serialize};

use super::StudioStore;
use crate::studio::paths::{SessionPaths, StudioPaths};
use crate::studio::records::WorkspaceRecord;

pub(crate) mod schema;
pub(crate) const WORKSPACE_MANIFEST_SCHEMA_VERSION: u32 = 2;
pub(crate) const SESSION_MANIFEST_SCHEMA_VERSION: u32 = 2;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct WorkspaceManifest {
    pub(crate) schema_version: u32,
    pub(crate) workspace_id: String,
    pub(crate) kind: WorkspaceKind,
    pub(crate) path: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) ssh_alias: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct SessionManifest {
    pub(crate) schema_version: u32,
    pub(crate) thread_id: String,
    pub(crate) workspace_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) parent_thread_id: Option<String>,
    pub(crate) root_thread_id: String,
    pub(crate) workspace_mode: ThreadWorkspaceMode,
    pub(crate) workspace_path: String,
    pub(crate) created_at: i64,
}

impl SessionManifest {
    pub(crate) fn from_thread(thread: &pl_protocol::Thread) -> Self {
        Self {
            schema_version: SESSION_MANIFEST_SCHEMA_VERSION,
            thread_id: thread.id.clone(),
            workspace_id: thread.workspace_id.clone(),
            parent_thread_id: thread.parent_thread_id.clone(),
            root_thread_id: thread.root_thread_id.clone(),
            workspace_mode: thread.workspace_mode,
            workspace_path: thread.workspace_path.clone(),
            created_at: thread.created_at,
        }
    }
}

impl StudioStore {
    pub(crate) fn registered_session_paths(&self, thread_id: &str) -> Result<SessionPaths> {
        let owner = self
            .catalog()
            .get(thread_id)
            .context("Thread is not registered in the Studio catalog")?;
        self.paths.session_paths(&owner.workspace_id, thread_id)
    }

    pub(crate) fn session_paths(
        &self,
        workspace_id: &str,
        thread_id: &str,
    ) -> Result<SessionPaths> {
        self.paths.session_paths(workspace_id, thread_id)
    }

    pub(crate) async fn prepare_workspace_manifest(
        &self,
        workspace: &WorkspaceRecord,
    ) -> Result<()> {
        persist_workspace_manifest(
            &self.paths,
            &WorkspaceManifest {
                schema_version: WORKSPACE_MANIFEST_SCHEMA_VERSION,
                workspace_id: workspace.id.clone(),
                kind: workspace.kind,
                path: workspace.path.clone(),
                ssh_alias: workspace.ssh_alias.clone(),
            },
        )
        .await
    }

    pub(crate) async fn prepare_session_manifest(
        &self,
        thread: &pl_protocol::Thread,
    ) -> Result<SessionPaths> {
        let session =
            persist_session_manifest(&self.paths, &SessionManifest::from_thread(thread)).await?;
        safe_path(&self.paths, &session.temp_dir()).await?;
        tokio::fs::create_dir_all(session.temp_dir()).await?;
        Ok(session)
    }
}

pub(crate) async fn persist_workspace_manifest(
    paths: &StudioPaths,
    expected: &WorkspaceManifest,
) -> Result<()> {
    ensure!(
        expected.schema_version == WORKSPACE_MANIFEST_SCHEMA_VERSION
            && !expected.workspace_id.is_empty()
            && !expected.path.is_empty(),
        "invalid Workspace manifest"
    );
    let path = paths.workspace_manifest(&expected.workspace_id)?;
    safe_path(paths, &path).await?;
    match tokio::fs::read_to_string(&path).await {
        Ok(content) => {
            let existing: WorkspaceManifest = toml::from_str(&content)?;
            ensure!(existing == *expected, "conflicting Workspace manifest");
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            write_manifest(&path, &schema::encode_workspace(expected)?).await?
        }
        Err(error) => return Err(error.into()),
    }
    Ok(())
}

pub(crate) async fn persist_session_manifest(
    paths: &StudioPaths,
    expected: &SessionManifest,
) -> Result<SessionPaths> {
    ensure!(
        expected.schema_version == SESSION_MANIFEST_SCHEMA_VERSION
            && !expected.thread_id.is_empty()
            && !expected.workspace_id.is_empty()
            && !expected.root_thread_id.is_empty(),
        "invalid session manifest"
    );
    ensure!(
        expected.parent_thread_id.is_some() || expected.root_thread_id == expected.thread_id,
        "root session is not its own root"
    );
    let session = paths.session_paths(&expected.workspace_id, &expected.thread_id)?;
    let path = session.session_manifest();
    safe_path(paths, &path).await?;
    match tokio::fs::read_to_string(&path).await {
        Ok(content) => {
            let existing: SessionManifest = toml::from_str(&content)?;
            ensure!(existing == *expected, "conflicting session manifest");
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            write_manifest(&path, &schema::encode_session(expected)?).await?
        }
        Err(error) => return Err(error.into()),
    }
    Ok(session)
}

pub(crate) async fn safe_path(paths: &StudioPaths, candidate: &Path) -> Result<()> {
    pl_tool::workspace::path_safety::validate_path_for_write_async(paths.home(), candidate)
        .await
        .with_context(|| format!("unsafe storage path: {}", candidate.display()))
}

pub(crate) async fn write_manifest(path: &Path, content: &str) -> Result<()> {
    let path = path.to_owned();
    let bytes = content.as_bytes().to_vec();
    tokio::task::spawn_blocking(move || pl_tool::workspace::write_file_atomically(&path, &bytes))
        .await??;
    Ok(())
}

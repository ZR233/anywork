use anyhow::Result;
use serde::{Deserialize, Serialize};
use version_migrate::{IntoDomain, Migrator, Versioned};

use super::{ProjectManifest, SessionManifest};

const PROJECT_ENTITY: &str = "project-manifest";
const SESSION_ENTITY: &str = "session-manifest";
const VERSION_KEY: &str = "schemaVersion";

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
enum WorkspaceModeV1 {
    Local,
    Worktree,
}

impl From<pl_protocol::ThreadWorkspaceMode> for WorkspaceModeV1 {
    fn from(value: pl_protocol::ThreadWorkspaceMode) -> Self {
        match value {
            pl_protocol::ThreadWorkspaceMode::Local => Self::Local,
            pl_protocol::ThreadWorkspaceMode::Worktree => Self::Worktree,
        }
    }
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
pub(super) struct ProjectManifestV1 {
    project_id: String,
    path: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    ssh_alias: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Versioned)]
#[versioned(version = "1.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct SessionManifestV1 {
    thread_id: String,
    project_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    parent_thread_id: Option<String>,
    root_thread_id: String,
    workspace_mode: WorkspaceModeV1,
    workspace_path: String,
    created_at: i64,
}

impl IntoDomain<ProjectManifestV1> for ProjectManifestV1 {
    fn into_domain(self) -> ProjectManifestV1 {
        self
    }
}

impl IntoDomain<SessionManifestV1> for SessionManifestV1 {
    fn into_domain(self) -> SessionManifestV1 {
        self
    }
}

impl From<ProjectManifestV1> for ProjectManifest {
    fn from(document: ProjectManifestV1) -> Self {
        Self {
            schema_version: super::PROJECT_MANIFEST_SCHEMA_VERSION,
            project_id: document.project_id,
            path: document.path,
            ssh_alias: document.ssh_alias,
        }
    }
}

impl From<SessionManifestV1> for SessionManifest {
    fn from(document: SessionManifestV1) -> Self {
        Self {
            schema_version: super::SESSION_MANIFEST_SCHEMA_VERSION,
            thread_id: document.thread_id,
            project_id: document.project_id,
            parent_thread_id: document.parent_thread_id,
            root_thread_id: document.root_thread_id,
            workspace_mode: document.workspace_mode.into(),
            workspace_path: document.workspace_path,
            created_at: document.created_at,
        }
    }
}

fn project_migrator() -> Result<Migrator> {
    let mut migrator = Migrator::new();
    migrator
        .register(
            Migrator::define(PROJECT_ENTITY)
                .with_keys(VERSION_KEY, "data")
                .from::<ProjectManifestV1>()
                .into::<ProjectManifestV1>(),
        )
        .map_err(|error| crate::toml_schema::chain_error(PROJECT_ENTITY, error))?;
    Ok(migrator)
}

fn session_migrator() -> Result<Migrator> {
    let mut migrator = Migrator::new();
    migrator
        .register(
            Migrator::define(SESSION_ENTITY)
                .with_keys(VERSION_KEY, "data")
                .from::<SessionManifestV1>()
                .into::<SessionManifestV1>(),
        )
        .map_err(|error| crate::toml_schema::chain_error(SESSION_ENTITY, error))?;
    Ok(migrator)
}

pub(super) fn decode_project(path: &std::path::Path, content: &str) -> Result<ProjectManifest> {
    let loaded = crate::toml_schema::load::<ProjectManifestV1, ProjectManifestV1>(
        path,
        content,
        &project_migrator()?,
        PROJECT_ENTITY,
        VERSION_KEY,
    )?;
    Ok(loaded.document.into())
}

pub(super) fn encode_project(document: &ProjectManifest) -> Result<String> {
    crate::toml_schema::encode(
        &ProjectManifestV1 {
            project_id: document.project_id.clone(),
            path: document.path.clone(),
            ssh_alias: document.ssh_alias.clone(),
        },
        VERSION_KEY,
    )
}

pub(super) fn decode_session(path: &std::path::Path, content: &str) -> Result<SessionManifest> {
    let loaded = crate::toml_schema::load::<SessionManifestV1, SessionManifestV1>(
        path,
        content,
        &session_migrator()?,
        SESSION_ENTITY,
        VERSION_KEY,
    )?;
    Ok(loaded.document.into())
}

pub(super) fn encode_session(document: &SessionManifest) -> Result<String> {
    crate::toml_schema::encode(
        &SessionManifestV1 {
            thread_id: document.thread_id.clone(),
            project_id: document.project_id.clone(),
            parent_thread_id: document.parent_thread_id.clone(),
            root_thread_id: document.root_thread_id.clone(),
            workspace_mode: document.workspace_mode.into(),
            workspace_path: document.workspace_path.clone(),
            created_at: document.created_at,
        },
        VERSION_KEY,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_protocol::ThreadWorkspaceMode;

    #[test]
    fn current_manifests_use_integer_header_and_round_trip() -> Result<()> {
        let project = ProjectManifest {
            schema_version: 1,
            project_id: "project-a".into(),
            path: "/workspace".into(),
            ssh_alias: Some("project-ssh".into()),
        };
        let encoded = encode_project(&project)?;
        assert!(encoded.contains("schemaVersion = 1"));
        assert_eq!(
            decode_project(std::path::Path::new("project.toml"), &encoded)?,
            project
        );

        let session = SessionManifest {
            schema_version: 1,
            thread_id: "thread-a".into(),
            project_id: "project-a".into(),
            parent_thread_id: Some("parent-a".into()),
            root_thread_id: "root-a".into(),
            workspace_mode: ThreadWorkspaceMode::Local,
            workspace_path: "/workspace".into(),
            created_at: 7,
        };
        let encoded = encode_session(&session)?;
        assert!(encoded.contains("schemaVersion = 1"));
        assert_eq!(
            decode_session(std::path::Path::new("session.toml"), &encoded)?,
            session
        );
        Ok(())
    }

    #[test]
    fn manifests_reject_future_and_missing_headers_as_document_migration_failures() {
        for content in [
            "schemaVersion = 99\nprojectId = 'project-a'\npath = '/workspace'\nsshAlias = 'project-ssh'\n",
            "",
        ] {
            let project_error = decode_project(std::path::Path::new("project.toml"), content)
                .expect_err("unsupported or missing schema header must fail");
            let session_content = if content.is_empty() {
                ""
            } else {
                "schemaVersion = 99\nthreadId = 'thread-a'\nprojectId = 'project-a'\nrootThreadId = 'thread-a'\nworkspaceMode = 'worktree'\nworkspacePath = '/workspace/thread-a'\ncreatedAt = 7\n"
            };
            let session_error =
                decode_session(std::path::Path::new("session.toml"), session_content)
                    .expect_err("unsupported or missing schema header must fail");
            for error in [&project_error, &session_error] {
                assert!(error.chain().any(|cause| {
                    cause
                        .downcast_ref::<crate::toml_schema::DocumentMigrationFailed>()
                        .is_some()
                }));
            }
        }
    }

    #[test]
    fn session_identity_validation_keeps_manifest_context() {
        let path = std::path::Path::new("session.toml");
        let existing = SessionManifest {
            schema_version: 1,
            thread_id: "thread-a".into(),
            project_id: "other-project".into(),
            parent_thread_id: None,
            root_thread_id: "thread-a".into(),
            workspace_mode: ThreadWorkspaceMode::Worktree,
            workspace_path: "/workspace/thread-a".into(),
            created_at: 7,
        };
        let expected = SessionManifest {
            project_id: "project-a".into(),
            ..existing.clone()
        };
        let error = super::super::ensure_session_manifest_compatible(path, &existing, &expected)
            .expect_err("project mismatch must fail");
        assert!(error.chain().any(|cause| {
            cause
                .downcast_ref::<crate::toml_schema::DocumentMigrationFailed>()
                .is_some()
        }));
        assert!(error.to_string().contains("session.toml"));
    }
}

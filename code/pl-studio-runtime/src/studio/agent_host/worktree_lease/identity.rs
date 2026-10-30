//! Frozen physical endpoint/path facts; resolution and persistence never hold admission locks.
use anyhow::{Context, Result, ensure};
use serde::{Deserialize, Serialize};
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub(crate) enum WorkspaceEndpoint {
    Local,
    Ssh {
        host: String,
        port: u16,
        username: String,
    },
}
impl WorkspaceEndpoint {
    pub(crate) fn from_profile(profile: Option<&pl_tool::remote::SshServerProfile>) -> Self {
        match profile {
            None => Self::Local,
            Some(profile) => Self::Ssh {
                host: profile.host_name.clone(),
                port: profile.port,
                username: profile.username.clone(),
            },
        }
    }
}

/// Only constructors supplied with OS/helper canonical results may create a new identity.
#[derive(Debug, Clone, Serialize, Deserialize, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct WorkspaceIdentity {
    pub endpoint: WorkspaceEndpoint,
    pub root: String,
}
impl PartialEq for WorkspaceIdentity {
    fn eq(&self, other: &Self) -> bool {
        self.endpoint == other.endpoint && self.matches_root(&other.root)
    }
}
impl WorkspaceIdentity {
    pub(crate) fn canonical(endpoint: WorkspaceEndpoint, root: String) -> Result<Self> {
        match &endpoint {
            WorkspaceEndpoint::Local => {
                ensure!(
                    Path::new(&root).is_absolute(),
                    "workspace identity is not absolute"
                );
                ensure!(
                    !Path::new(&root).components().any(|part| matches!(
                        part,
                        std::path::Component::ParentDir | std::path::Component::CurDir
                    )),
                    "workspace identity is not normalized"
                );
            }
            WorkspaceEndpoint::Ssh { .. } => ensure!(
                pl_tool::remote::normalize_remote_absolute_path(&root)? == root,
                "SSH workspace identity is not canonical POSIX"
            ),
        }
        Ok(Self { endpoint, root })
    }
    /// Compares a frozen root without resolving or rebinding it. Only local paths use the host's
    /// component semantics and safe Windows prefix simplification; SSH paths stay POSIX strings.
    pub(crate) fn matches_root(&self, root: &str) -> bool {
        match self.endpoint {
            WorkspaceEndpoint::Local => {
                dunce::simplified(Path::new(&self.root)) == dunce::simplified(Path::new(root))
            }
            WorkspaceEndpoint::Ssh { .. } => self.root == root,
        }
    }
    pub(crate) fn within(&self, outer: &Self) -> bool {
        if self.endpoint != outer.endpoint {
            return false;
        }
        match self.endpoint {
            WorkspaceEndpoint::Local => dunce::simplified(Path::new(&self.root))
                .starts_with(dunce::simplified(Path::new(&outer.root))),
            WorkspaceEndpoint::Ssh { .. } => {
                self.root == outer.root
                    || self
                        .root
                        .strip_prefix(outer.root.trim_end_matches('/'))
                        .is_some_and(|suffix| suffix.starts_with('/'))
            }
        }
    }
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct SavedWorkspaceIdentity {
    owner: String,
    pub identity: WorkspaceIdentity,
}
impl crate::studio::store::object::PersistedStudioObject for SavedWorkspaceIdentity {
    type PersistenceDto = Self;
    const OWNER_KIND: &'static str = "thread";
    const OBJECT_KIND: &'static str = "workspaceIdentity";
    const SCHEMA_VERSION: i64 = 1;
    fn revision(&self) -> u64 {
        1
    }
    fn to_persistence_dto(&self) -> Self {
        self.clone()
    }
    fn from_persistence_dto(dto: Self) -> Result<Self> {
        WorkspaceIdentity::canonical(dto.identity.endpoint.clone(), dto.identity.root.clone())?;
        Ok(dto)
    }
    fn validate_owner(&self, id: &str) -> Result<()> {
        ensure!(self.owner == id, "workspace identity owner mismatch");
        Ok(())
    }
}
impl crate::studio::StudioStore {
    pub(in crate::studio) async fn workspace_identity(
        &self,
        owner: &str,
    ) -> Result<Option<WorkspaceIdentity>> {
        Ok(
            crate::studio::store::object::load_object::<SavedWorkspaceIdentity>(
                self.database(),
                owner,
            )
            .await?
            .map(|saved| saved.identity),
        )
    }
    pub(in crate::studio) async fn bind_workspace_identity(
        &self,
        owner: &str,
        identity: &WorkspaceIdentity,
    ) -> Result<()> {
        use crate::studio::store::object::{load_object, put_object};
        if let Some(saved) = load_object::<SavedWorkspaceIdentity>(self.database(), owner).await? {
            ensure!(
                saved.identity == *identity,
                "frozen physical workspace identity changed for {owner}"
            );
            return Ok(());
        }
        put_object(
            self.database(),
            owner,
            &SavedWorkspaceIdentity {
                owner: owner.into(),
                identity: identity.clone(),
            },
            crate::studio::unix_seconds(),
        )
        .await?;
        let saved = load_object::<SavedWorkspaceIdentity>(self.database(), owner)
            .await?
            .context("workspace identity durable ACK is missing")?;
        ensure!(
            saved.identity == *identity,
            "workspace identity durable ACK changed for {owner}"
        );
        Ok(())
    }
}

pub(in crate::studio) async fn resolve_physical_workspace(
    ssh: &pl_tool::remote::SshManager,
    project: &crate::studio::WorkspaceRecord,
    root: &Path,
) -> Result<WorkspaceIdentity> {
    match project.ssh_alias.as_deref() {
        Some(alias) => {
            let host = ssh
                .open_workspace_host(alias, root.to_string_lossy().into_owned())
                .await?;
            WorkspaceIdentity::canonical(
                WorkspaceEndpoint::from_profile(Some(&host.profile)),
                host.files.canonical_path().into(),
            )
        }
        None => {
            let path = root.to_owned();
            let canonical =
                tokio::task::spawn_blocking(move || dunce::canonicalize(path)).await??;
            WorkspaceIdentity::canonical(
                WorkspaceEndpoint::Local,
                canonical.to_string_lossy().into_owned(),
            )
        }
    }
}

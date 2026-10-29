//! Typed SSH management commands delegated to `pl-tool::remote`.

use anyhow::Result;
use pl_protocol::remote::RemoteDirectoryListing;
use pl_tool::remote::{SshConnectionSnapshot, SshServerProfile};

use crate::studio::records::ProjectRecord;
use crate::studio::store::directory::{DirectoryDelta, ProjectDirectoryRecord};

use super::StudioRuntime;

/// SSH 服务器密码更新语义，与供应商 API Key 更新保持一致。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SshPasswordUpdate {
    Preserve,
    Replace { value: String },
    Clear,
}

/// Studio 暴露的 SSH 服务器运行时条目（不携带密码明文，只暴露 `has_password`）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SshServerRuntimeEntry {
    pub profile: SshServerProfile,
    pub managed: bool,
    pub has_password: bool,
}

impl StudioRuntime {
    pub(super) async fn hydrate_ssh_servers(&self) -> Result<()> {
        self.ssh_manager
            .reload_servers()
            .await
            .map_err(|error| anyhow::anyhow!(error))?;
        for entry in self.ssh_manager.list_servers().await {
            self.ensure_ssh_password_hydrated(&entry.profile.alias)
                .await;
        }
        Ok(())
    }

    async fn ensure_ssh_password_hydrated(&self, alias: &str) {
        if self.ssh_manager.has_server_password(alias).await {
            return;
        }
        if let Ok(Some(password)) = self.config_runtime.load_ssh_password(alias) {
            self.ssh_manager
                .set_server_password(alias, Some(password))
                .await;
        }
    }

    pub async fn list_ssh_servers(&self) -> Result<Vec<SshServerRuntimeEntry>> {
        // 以文件为唯一事实源；每次列表都重新解析，拾取手工编辑。
        self.hydrate_ssh_servers().await?;
        let entries = self.ssh_manager.list_servers().await;
        let mut out = Vec::with_capacity(entries.len());
        for entry in entries {
            let has_password = self
                .ssh_manager
                .has_server_password(&entry.profile.alias)
                .await;
            out.push(SshServerRuntimeEntry {
                profile: entry.profile,
                managed: entry.managed,
                has_password,
            });
        }
        Ok(out)
    }

    pub async fn save_ssh_server(
        &self,
        profile: SshServerProfile,
        password: SshPasswordUpdate,
    ) -> Result<SshServerRuntimeEntry> {
        if let SshPasswordUpdate::Replace { ref value } = password
            && value.trim().is_empty()
        {
            return Err(pl_protocol::studio::StudioError::invalid_argument(
                "SSH password must not be empty",
            )
            .into());
        }
        let previous = self
            .ssh_manager
            .list_servers()
            .await
            .into_iter()
            .find(|server| server.profile.alias == profile.alias)
            .map(|server| server.profile);
        let profile = self
            .ssh_manager
            .save_server(profile)
            .await
            .map_err(|error| anyhow::anyhow!(error))?;
        let password_changed = match password {
            SshPasswordUpdate::Preserve => {
                self.ensure_ssh_password_hydrated(&profile.alias).await;
                false
            }
            SshPasswordUpdate::Replace { value } => {
                self.config_runtime
                    .save_ssh_password(&profile.alias, &value)
                    .map_err(|error| anyhow::anyhow!(error))?;
                self.ssh_manager
                    .set_server_password(&profile.alias, Some(value))
                    .await;
                let _ = self.ssh_manager.disconnect_server(&profile.alias).await;
                true
            }
            SshPasswordUpdate::Clear => {
                self.config_runtime
                    .delete_ssh_password(&profile.alias)
                    .map_err(|error| anyhow::anyhow!(error))?;
                self.ssh_manager
                    .set_server_password(&profile.alias, None)
                    .await;
                let _ = self.ssh_manager.disconnect_server(&profile.alias).await;
                true
            }
        };
        if previous.as_ref() != Some(&profile) || password_changed {
            self.thread_factory.invalidate_ssh_bindings(&profile.alias);
            self.tool_catalog_updates.notify_one();
        }
        let has_password = self.ssh_manager.has_server_password(&profile.alias).await;
        Ok(SshServerRuntimeEntry {
            profile,
            managed: true,
            has_password,
        })
    }

    pub async fn delete_ssh_server(&self, alias: &str) -> Result<()> {
        self.ssh_manager
            .delete_server(alias)
            .await
            .map_err(|error| anyhow::anyhow!(error))?;
        let _ = self.config_runtime.delete_ssh_password(alias);
        self.thread_factory.invalidate_ssh_bindings(alias);
        self.tool_catalog_updates.notify_one();
        Ok(())
    }

    pub async fn authenticate_ssh_server(
        &self,
        alias: &str,
        password: String,
        remember_password: bool,
    ) -> Result<SshConnectionSnapshot> {
        if password.trim().is_empty() {
            return Err(pl_protocol::studio::StudioError::invalid_argument(
                "SSH password must not be empty",
            )
            .into());
        }
        let previous = self.ssh_manager.server_password(alias).await;
        self.ssh_manager
            .set_server_password(alias, Some(password.clone()))
            .await;
        match self.ssh_manager.test_connection(alias).await {
            Ok(snapshot) => {
                if remember_password {
                    self.config_runtime
                        .save_ssh_password(alias, &password)
                        .map_err(|error| anyhow::anyhow!(error))?;
                }
                Ok(snapshot)
            }
            Err(error) => {
                self.ssh_manager.set_server_password(alias, previous).await;
                Err(anyhow::anyhow!(error))
            }
        }
    }

    pub async fn test_ssh_connection(&self, alias: &str) -> Result<SshConnectionSnapshot> {
        self.ensure_ssh_password_hydrated(alias).await;
        self.ssh_manager
            .test_connection(alias)
            .await
            .map_err(|error| anyhow::anyhow!(error))
    }

    pub async fn reconnect_ssh_server(&self, alias: &str) -> Result<SshConnectionSnapshot> {
        self.ensure_ssh_password_hydrated(alias).await;
        self.ssh_manager
            .reconnect_server(alias)
            .await
            .map_err(|error| anyhow::anyhow!(error))?;
        Ok(self.ssh_manager.connection_snapshot(alias).await?)
    }

    pub async fn browse_remote_directories(
        &self,
        alias: &str,
        path: Option<String>,
        cursor: Option<String>,
    ) -> Result<RemoteDirectoryListing> {
        self.ensure_ssh_password_hydrated(alias).await;
        self.ssh_manager
            .browse_directories(alias, path, cursor)
            .await
            .map_err(|error| anyhow::anyhow!(error))
    }

    pub async fn close_remote_directory(&self, alias: &str, cursor: String) -> Result<()> {
        self.ssh_manager
            .close_directory(alias, cursor)
            .await
            .map_err(|error| anyhow::anyhow!(error))
    }

    pub async fn open_remote_project(&self, alias: &str, path: String) -> Result<ProjectRecord> {
        self.ensure_ssh_password_hydrated(alias).await;
        let workspace = self
            .ssh_manager
            .open_workspace(alias, path)
            .await
            .map_err(|error| anyhow::anyhow!(error))?;
        let canonical_path = workspace.canonical_path().to_string();
        let _guard = self.lifecycle_lock.lock().await;
        if let Some(project) = self
            .agent_facility
            .product_events
            .project_snapshot()
            .await
            .into_iter()
            .find(|project| {
                project.path == canonical_path && project.ssh_alias.as_deref() == Some(alias)
            })
        {
            return Ok(project);
        }
        let name = canonical_path
            .trim_end_matches('/')
            .rsplit('/')
            .next()
            .filter(|name| !name.is_empty())
            .unwrap_or("remote-workspace")
            .to_string();
        let now = crate::studio::unix_seconds();
        let existing = self
            .store
            .find_project_by_path(&canonical_path, Some(alias))
            .await?;
        let (id, created_at, name) = existing
            .map(|row| (row.id, row.created_at, row.name))
            .unwrap_or_else(|| (crate::studio::ids::new_id("project"), now, name));
        let delta = ProjectDirectoryRecord {
            id: id.clone(),
            kind: pl_protocol::studio::WorkspaceKind::Project,
            name: name.clone(),
            path: canonical_path.clone(),
            ssh_alias: Some(alias.to_string()),
            created_at,
            updated_at: now,
            last_opened_at: Some(now),
            closed: false,
        };
        self.agent_facility
            .product_events
            .commit_directory(DirectoryDelta::upsert_project(delta))
            .await?;
        Ok(ProjectRecord {
            id,
            kind: pl_protocol::studio::WorkspaceKind::Project,
            name,
            path: canonical_path,
            ssh_alias: Some(alias.to_string()),
            updated_at: now,
        })
    }
}

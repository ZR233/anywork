use anyhow::Result;

use crate::{StudioSkillsStateSnapshot, StudioStateSnapshot, StudioThreadDirectoryPage};

use super::StudioRuntime;

const STATE_THREAD_PAGE_LIMIT: usize = 50;

impl StudioRuntime {
    /// Reads the complete canonical Studio state without causing lifecycle side effects.
    pub async fn read_state(&self) -> Result<StudioStateSnapshot> {
        let runtime = self.runtime_snapshot().await?;
        let project_directory = self
            .agent_facility
            .product_events
            .read_project_directory()
            .await?;
        let thread_directory = self
            .agent_facility
            .product_events
            .read_thread_directory_page(None, STATE_THREAD_PAGE_LIMIT)
            .await?;
        let agent_directory = self
            .agent_facility
            .product_events
            .read_agent_directory()
            .await;
        // 同一 Settings command 边界内投影配置与 ACP 身份，避免读到提交与身份对齐之间的状态。
        let projected = self
            .config_runtime
            .with_consistent_snapshot(|settings, catalog| {
                let acp_accounts = self
                    .acp_auth
                    .settings_view(settings.revision, &settings.acp)?;
                Ok::<_, anyhow::Error>((
                    super::settings_api::settings_config_snapshot(settings, acp_accounts)?,
                    super::settings_api::model_catalog_snapshot(settings, catalog)?,
                ))
            })?;
        let (settings_config, model_catalog) = projected?;
        let recovery = crate::StudioRecoveryStateSnapshot {
            state: self.recovery.state(),
        };
        let host_mcp_catalog = self.read_mcp_catalog(&pl_protocol::McpScope::Host)?;
        let lsp = self.read_lsp_state().await;
        let mut skills_by_project = Vec::new();
        if let Some(directory) = project_directory.state.value() {
            skills_by_project.reserve(directory.projects.len());
            for project in &directory.projects {
                skills_by_project.push(StudioSkillsStateSnapshot::from(
                    self.skills.read(&project.id).await,
                ));
            }
        }
        let session_costs = self.model_performance.published_session_costs().await;
        Ok(StudioStateSnapshot {
            owner_epoch: self.owner_epoch.clone(),
            runtime,
            project_directory,
            thread_directory,
            agent_directory,
            settings_config: crate::StudioSettingsConfigStateSnapshot {
                state: pl_protocol::ObservedResource::ready(
                    settings_config.revision,
                    settings_config.updated_at,
                    settings_config,
                ),
            },
            model_catalog: crate::StudioModelCatalogStateSnapshot {
                state: pl_protocol::ObservedResource::ready(
                    model_catalog.revision,
                    model_catalog.updated_at,
                    model_catalog,
                ),
            },
            recovery,
            host_mcp_catalog,
            lsp,
            skills_by_project,
            thread_mode_catalog: self.read_thread_mode_catalog(),
            account_usage: self.read_account_usage_state().await,
            session_costs,
            updater: self.read_update_state().await,
            persistence: self.agent_facility.product_events.persistence_state(),
            persistence_queue: self.agent_facility.product_events.persistence_queue_state(),
            agent_profiles: self.read_agent_profiles_state()?,
            bots: self.bots.snapshot().await,
        })
    }

    /// Reads a keyset-paginated Thread directory page from the canonical in-memory index.
    pub async fn list_threads_page(
        &self,
        cursor: Option<&str>,
        limit: usize,
    ) -> Result<StudioThreadDirectoryPage> {
        self.agent_facility
            .product_events
            .read_thread_directory_page(cursor, limit)
            .await
    }

    pub async fn query_threads(
        &self,
        query: &pl_protocol::studio::ThreadDirectoryQuery,
        cursor: Option<&str>,
        limit: usize,
    ) -> Result<StudioThreadDirectoryPage> {
        self.agent_facility
            .product_events
            .query_threads(query, cursor, limit)
            .await
    }

    /// Reads one canonical Thread without activating its actor.
    pub async fn read_thread(&self, thread_id: &str) -> Result<pl_protocol::Thread> {
        self.read_protocol_thread(thread_id).await
    }

    /// Reads a Project Skills owner snapshot without scanning the filesystem.
    pub async fn read_skills_state(&self, workspace_id: &str) -> StudioSkillsStateSnapshot {
        self.skills.read(workspace_id).await.into()
    }

    /// Reads the current process-wide Thread Mode catalog.
    pub fn read_thread_mode_catalog(&self) -> pl_protocol::ThreadModeCatalogSnapshot {
        self.config_runtime.read_thread_mode_catalog()
    }
}

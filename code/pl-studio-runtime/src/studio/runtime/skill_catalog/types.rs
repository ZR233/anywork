//! Project Skills catalog 的核心类型：运行时 owner、状态快照与本地 registry 构造。

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::Arc;

use crate::studio::ids::unix_seconds;
use anyhow::{Context, Result};
use pl_protocol::ObservedResource;
use pl_tool::skill::{
    FileSystemSkillProvider, FrozenSkillCatalog, SkillProviderRegistration, SkillRegistry,
    SkillSummary,
};
use serde::{Deserialize, Serialize};
use tokio::sync::{Mutex, RwLock};

use super::system;

/// Project skills catalog 的唯一内存 owner。
#[derive(Clone)]
pub struct SkillCatalogRuntime {
    pub(super) command_lock: Arc<Mutex<()>>,
    pub(super) states: Arc<RwLock<BTreeMap<String, SkillsStateSnapshot>>>,
    pub(super) events: Option<crate::ProductEventBus>,
    pub(super) system_skills_dir: Option<Arc<PathBuf>>,
    pub(super) registry: SkillRegistry,
    pub(super) search_options: pl_tool::skill::SkillSearchOptions,
    pub(super) local_executor:
        std::result::Result<pl_remote_helper::Executor, pl_remote_helper::ExecutionError>,
    _provider_registrations: Vec<Arc<SkillProviderRegistration>>,
}

/// 某 Project 已发布且可被未来 Turn 冻结的 catalog。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillsStateSnapshot {
    pub workspace_id: String,
    pub state: ObservedResource<SkillsStateData>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillsStateData {
    pub config_fingerprint: String,
    pub catalog_revision: u64,
    pub catalog: Arc<FrozenSkillCatalog>,
}

/// Cached Studio Skill search result over one published catalog revision.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SkillSearchResult {
    pub workspace_id: String,
    pub catalog_revision: u64,
    pub matches: Vec<SkillSummary>,
    pub truncated: bool,
}

impl SkillsStateSnapshot {
    pub(in crate::studio) fn catalog_for_turn(&self) -> Option<Arc<FrozenSkillCatalog>> {
        self.state.value().map(|data| data.catalog.clone())
    }
}

impl SkillCatalogRuntime {
    /// Creates the Studio catalog owner with its product-owned system Skills directory.
    pub fn new(
        events: crate::ProductEventBus,
        system_skills_dir: PathBuf,
        executor: pl_remote_helper::Executor,
        search_options: pl_tool::skill::SkillSearchOptions,
    ) -> Self {
        tracing::debug!(include_default_user_dir = search_options.include_default_user_dir, additional_dirs = ?search_options.additional_dirs, "Skill search policy");
        let (registry, provider_registrations) = local_registry(search_options.clone());
        Self {
            command_lock: Arc::new(Mutex::new(())),
            states: Arc::new(RwLock::new(BTreeMap::new())),
            events: Some(events),
            local_executor: Ok(executor),
            system_skills_dir: Some(Arc::new(system_skills_dir)),
            registry,
            search_options,
            _provider_registrations: provider_registrations,
        }
    }

    pub(in crate::studio::runtime) async fn refresh_system_skills(&self) -> Result<()> {
        let system_skills_dir = self
            .system_skills_dir
            .as_ref()
            .context("system Skills directory is not configured")?
            .as_ref()
            .clone();
        tokio::task::spawn_blocking(move || system::refresh_system_skills(&system_skills_dir))
            .await
            .map_err(|error| anyhow::anyhow!("system Skills refresh task failed: {error}"))?
    }
}

impl Default for SkillCatalogRuntime {
    fn default() -> Self {
        let (registry, provider_registrations) = local_registry(Default::default());
        Self {
            command_lock: Arc::new(Mutex::new(())),
            states: Arc::new(RwLock::new(BTreeMap::new())),
            events: None,
            local_executor: pl_remote_helper::Executor::local(),
            system_skills_dir: None,
            registry,
            search_options: Default::default(),
            _provider_registrations: provider_registrations,
        }
    }
}

pub(super) fn empty_snapshot(workspace_id: &str) -> SkillsStateSnapshot {
    SkillsStateSnapshot {
        workspace_id: workspace_id.to_string(),
        state: ObservedResource::uninitialized(unix_seconds()),
    }
}

fn local_registry(
    search_options: pl_tool::skill::SkillSearchOptions,
) -> (SkillRegistry, Vec<Arc<SkillProviderRegistration>>) {
    let registry = SkillRegistry::new();
    let mut registrations = Vec::new();
    if let Ok(registration) = registry
        .register(Arc::new(
            FileSystemSkillProvider::configured_readonly_with_options(search_options),
        ))
        .map(Arc::new)
        .map_err(|error| tracing::error!(%error, "failed to register filesystem Skill provider"))
    {
        registrations.push(registration);
    }
    (registry, registrations)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn failed_required_source_never_prepares_a_turn_from_last_good_or_empty_catalog()
    -> Result<()> {
        let root = tempfile::tempdir()?;
        let workspace = root.path().join("workspace");
        let extra = root.path().join("extra");
        std::fs::create_dir_all(&workspace)?;
        std::fs::create_dir_all(extra.join("required-skill"))?;
        std::fs::write(
            extra.join("required-skill/SKILL.md"),
            "---\nname: required-skill\ndescription: original catalog\n---\nbody\n",
        )?;
        let options =
            pl_tool::skill::SkillSearchOptions::resolve(false, [extra.clone()], root.path())?;
        let (registry, registrations) = local_registry(options.clone());
        let owner = SkillCatalogRuntime {
            registry,
            _provider_registrations: registrations,
            search_options: options,
            ..Default::default()
        };
        let config = pl_tool::skill::SkillsConfig {
            system: pl_tool::skill::SystemSkillsConfig { enabled: false },
            ..Default::default()
        };
        let prepared = owner
            .prepare_thread_catalog(
                "project",
                &workspace,
                &config,
                tokio_util::sync::CancellationToken::new(),
                None,
            )
            .await?
            .context("complete preparation")?;
        assert!(prepared.0.find("required-skill").is_some());
        std::fs::remove_dir_all(&extra)?;
        assert!(
            owner
                .prepare_thread_catalog(
                    "project",
                    &workspace,
                    &config,
                    tokio_util::sync::CancellationToken::new(),
                    None
                )
                .await
                .is_err()
        );
        let snapshot = owner.read("project").await;
        assert_eq!(
            snapshot.state.kind(),
            pl_protocol::ObservedResourceKind::Degraded
        );
        assert!(
            snapshot.state.value().is_some(),
            "Settings may still display last-good data"
        );
        assert!(
            owner
                .prepare_thread_catalog(
                    "new-project",
                    &workspace,
                    &config,
                    tokio_util::sync::CancellationToken::new(),
                    None
                )
                .await
                .is_err()
        );
        assert_eq!(
            owner.read("new-project").await.state.kind(),
            pl_protocol::ObservedResourceKind::Failed
        );
        Ok(())
    }
}

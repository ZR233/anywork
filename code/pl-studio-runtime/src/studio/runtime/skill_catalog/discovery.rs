//! Project Skills catalog 的显式发现：扫描 provider、原子发布并维护 revision 与指纹。

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::Path;
use std::sync::Arc;

use crate::studio::ids::unix_seconds;
use anyhow::{Context, Error, Result};
use pl_protocol::{ObservedResourceCommand, ObservedResourceKind, StateError, StateOperation};
use pl_tool::skill::SkillsConfig;
use pl_tool::skill::{
    FrozenSkillCatalog, SkillCatalog, SkillDiscoverySources, SkillProviderRequest,
};

use super::{SkillCatalogRuntime, SkillsStateData, SkillsStateSnapshot};

/// 一次显式发现的 provider 来源。
enum DiscoverySource {
    Local,
    Remote(Arc<pl_tool::workspace_file::ExecutorWorkspaceFileBackend>),
}

impl SkillCatalogRuntime {
    /// 显式扫描并原子发布 Project catalog。
    pub async fn discover(
        &self,
        workspace_id: &str,
        workspace_root: &Path,
        config: &SkillsConfig,
    ) -> Result<SkillsStateSnapshot> {
        self.discover_with_cancellation(
            workspace_id,
            workspace_root,
            config,
            tokio_util::sync::CancellationToken::new(),
        )
        .await
    }

    /// 对一个远端 workspace 执行显式扫描并发布 Project catalog。
    ///
    /// 远端 provider 贡献 Project 源；本地 user/system 目录与
    /// Turn 使用同一套组合，保证设置页与 Turn 看到一致的技能目录。
    pub async fn discover_remote(
        &self,
        workspace_id: &str,
        workspace_root: &Path,
        config: &SkillsConfig,
        cancellation: tokio_util::sync::CancellationToken,
        remote_backend: Arc<pl_tool::workspace_file::ExecutorWorkspaceFileBackend>,
    ) -> Result<SkillsStateSnapshot> {
        self.discover_from_source(
            workspace_id,
            workspace_root,
            config,
            cancellation,
            DiscoverySource::Remote(remote_backend),
        )
        .await
        .map(|(snapshot, _)| snapshot)
    }

    pub async fn discover_with_cancellation(
        &self,
        workspace_id: &str,
        workspace_root: &Path,
        config: &SkillsConfig,
        cancellation: tokio_util::sync::CancellationToken,
    ) -> Result<SkillsStateSnapshot> {
        self.discover_from_source(
            workspace_id,
            workspace_root,
            config,
            cancellation,
            DiscoverySource::Local,
        )
        .await
        .map(|(snapshot, _)| snapshot)
    }

    /// Publishes preparation discovery while keeping the current source capability separate
    /// from any last-good catalog retained by the Settings state machine.
    pub(in crate::studio) async fn prepare_thread_catalog(
        &self,
        workspace_id: &str,
        workspace_root: &Path,
        config: &SkillsConfig,
        cancellation: tokio_util::sync::CancellationToken,
        remote: Option<Arc<pl_tool::workspace_file::ExecutorWorkspaceFileBackend>>,
    ) -> Result<Option<(Arc<FrozenSkillCatalog>, SkillDiscoverySources)>> {
        let source = remote.map_or(DiscoverySource::Local, DiscoverySource::Remote);
        let (snapshot, sources) = self
            .discover_from_source(workspace_id, workspace_root, config, cancellation, source)
            .await?;
        // Last-good data may remain visible in Settings, but cannot authorize a new model input.
        let error = match &snapshot.state {
            pl_protocol::ObservedResource::Degraded(state) => Some(state.error()),
            pl_protocol::ObservedResource::Failed(state) => Some(state.error()),
            _ => None,
        };
        if let Some(error) = error {
            return Err(pl_protocol::PureError::ConfigError(format!(
                "{}: {}",
                error.code, error.message
            ))
            .into());
        }
        anyhow::ensure!(
            snapshot.state.kind() == ObservedResourceKind::Ready,
            "Skill preparation did not publish a complete catalog"
        );
        Ok(snapshot
            .catalog_for_turn()
            .map(|catalog| (catalog, sources)))
    }

    async fn discover_from_source(
        &self,
        workspace_id: &str,
        workspace_root: &Path,
        config: &SkillsConfig,
        cancellation: tokio_util::sync::CancellationToken,
        source: DiscoverySource,
    ) -> Result<(SkillsStateSnapshot, SkillDiscoverySources)> {
        let _command = tokio::select! {
            biased;
            () = cancellation.cancelled() => anyhow::bail!("Skill discovery cancelled"),
            command = self.command_lock.lock() => command,
        };
        let fingerprint = self.fingerprint(config)?;
        let previous = self.read(workspace_id).await;
        let revision = previous.state.revision();
        let operation_id = format!("skills-discover-{}", revision.saturating_add(1));
        let running = SkillsStateSnapshot {
            workspace_id: workspace_id.to_string(),
            state: previous
                .state
                .decide(ObservedResourceCommand::Begin {
                    expected_revision: revision,
                    operation: StateOperation::Discover,
                    operation_id,
                    started_at: unix_seconds(),
                })
                .map_err(|error| anyhow::anyhow!(error.to_string()))?
                .next_state,
        };
        self.publish(workspace_id, running.clone()).await;

        let workspace_root = workspace_root.to_path_buf();
        let config = config.clone();
        let discovered = async {
            let files = match source {
                DiscoverySource::Local => {
                    let executor = self
                        .local_executor
                        .as_ref()
                        .map_err(|error| anyhow::anyhow!(error.clone()))?
                        .clone();
                    Arc::new(pl_tool::workspace_file::ExecutorWorkspaceFileBackend::new(
                        executor,
                        workspace_root
                            .to_str()
                            .context("Skill workspace path is not UTF-8")?,
                    )?)
                }
                DiscoverySource::Remote(files) => files,
            };
            self.registry
                .discover_project(
                    SkillProviderRequest {
                        workspace_root,
                        config,
                        system_dir: self.system_skills_dir(),
                        cancellation,
                    },
                    files,
                )
                .await
                .map_err(Error::from)
        }
        .await;
        let catalog = match discovered {
            Ok(catalog) => catalog,
            Err(error) => {
                let checked_at = unix_seconds();
                let failed = SkillsStateSnapshot {
                    workspace_id: workspace_id.to_string(),
                    state: running
                        .state
                        .decide(ObservedResourceCommand::Fail {
                            expected_revision: running.state.revision(),
                            failed_at: checked_at,
                            error: StateError {
                                code: "skillsDiscoveryFailed".to_string(),
                                message: format!("{error:#}"),
                                retryable: true,
                            },
                        })
                        .map_err(|transition| anyhow::anyhow!(transition.to_string()))?
                        .next_state,
                };
                self.publish(workspace_id, failed).await;
                return Err(error);
            }
        };
        let sources = catalog.discovery_sources();
        let checked_at = unix_seconds();
        if !catalog.snapshot().complete {
            let failed = SkillsStateSnapshot {
                workspace_id: workspace_id.to_string(),
                state: running
                    .state
                    .decide(ObservedResourceCommand::Fail {
                        expected_revision: running.state.revision(),
                        failed_at: checked_at,
                        error: StateError {
                            code: "skillsDiscoveryIncomplete".to_string(),
                            message: catalog.snapshot().warnings.join("; "),
                            retryable: true,
                        },
                    })
                    .map_err(|transition| anyhow::anyhow!(transition.to_string()))?
                    .next_state,
            };
            self.publish(workspace_id, failed.clone()).await;
            return Ok((failed, sources));
        }
        let catalog_revision = previous.state.value().map_or(1, |data| {
            if catalog_content_eq(data.catalog.snapshot(), catalog.snapshot()) {
                data.catalog_revision
            } else {
                data.catalog_revision.saturating_add(1)
            }
        });
        let snapshot = SkillsStateSnapshot {
            workspace_id: workspace_id.to_string(),
            state: running
                .state
                .decide(ObservedResourceCommand::Succeed {
                    expected_revision: running.state.revision(),
                    updated_at: checked_at,
                    last_checked_at: Some(checked_at),
                    value: SkillsStateData {
                        config_fingerprint: fingerprint,
                        catalog_revision,
                        catalog: Arc::new(catalog),
                    },
                })
                .map_err(|error| anyhow::anyhow!(error.to_string()))?
                .next_state,
        };
        self.publish(workspace_id, snapshot.clone()).await;
        Ok((snapshot, sources))
    }

    /// Settings 变化只标记旧 payload stale，不执行扫描。
    pub async fn mark_all_stale(&self) {
        let _command = self.command_lock.lock().await;
        let mut states = self.states.write().await;
        let mut changed = Vec::new();
        for state in states.values_mut() {
            if state.state.kind() == ObservedResourceKind::Ready {
                let Some(value) = state.state.value().cloned() else {
                    continue;
                };
                let decision = state.state.decide(ObservedResourceCommand::MarkStale {
                    expected_revision: state.state.revision(),
                    stale_at: unix_seconds(),
                    value,
                });
                if let Ok(decision) = decision {
                    state.state = decision.next_state;
                    changed.push(state.clone());
                }
            }
        }
        drop(states);
        if let Some(events) = &self.events {
            for state in changed {
                events.emit_skills_state(state);
            }
        }
    }

    async fn publish(&self, workspace_id: &str, snapshot: SkillsStateSnapshot) {
        self.states
            .write()
            .await
            .insert(workspace_id.to_string(), snapshot.clone());
        if let Some(events) = &self.events {
            events.emit_skills_state(snapshot);
        }
    }
}

fn catalog_content_eq(left: &SkillCatalog, right: &SkillCatalog) -> bool {
    left.project_dir == right.project_dir && left.skills == right.skills
}

impl SkillCatalogRuntime {
    pub(in crate::studio::runtime) fn fingerprint(&self, config: &SkillsConfig) -> Result<String> {
        let serialized = serde_json::to_vec(config)?;
        let mut hasher = DefaultHasher::new();
        serialized.hash(&mut hasher);
        self.search_options.hash(&mut hasher);
        Ok(format!("{:x}", hasher.finish()))
    }
}

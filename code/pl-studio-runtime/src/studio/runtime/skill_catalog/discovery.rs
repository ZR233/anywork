//! Project Skills catalog 的显式发现：扫描 provider、原子发布并维护 revision 与指纹。

use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::Path;
use std::sync::Arc;

use crate::studio::ids::unix_seconds;
use anyhow::{Error, Result};
use pl_protocol::{ObservedResourceCommand, ObservedResourceKind, StateError, StateOperation};
use pl_tool::skill::SkillsConfig;
use pl_tool::skill::{
    FrozenSkillCatalog, SkillCatalog, SkillDiscoverySources, SkillProviderRequest,
};

use super::super::skills::SkillsDiscovery;
use super::remote;
use super::{SkillCatalogRuntime, SkillsStateData, SkillsStateSnapshot};

/// 一次显式发现的 provider 来源。
enum DiscoverySource {
    Local,
    Remote(Arc<pl_tool::remote::RemoteWorkspaceFileBackend>),
}

impl SkillCatalogRuntime {
    /// 显式扫描并原子发布 Project catalog。
    pub async fn discover(
        &self,
        project_id: &str,
        workspace_root: &Path,
        config: &SkillsConfig,
    ) -> Result<SkillsStateSnapshot> {
        self.discover_with_cancellation(
            project_id,
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
        project_id: &str,
        workspace_root: &Path,
        config: &SkillsConfig,
        cancellation: tokio_util::sync::CancellationToken,
        remote_backend: Arc<pl_tool::remote::RemoteWorkspaceFileBackend>,
    ) -> Result<SkillsStateSnapshot> {
        self.discover_from_source(
            project_id,
            workspace_root,
            config,
            cancellation,
            DiscoverySource::Remote(remote_backend),
        )
        .await
        .map(|(capture, _)| capture.snapshot)
    }

    pub async fn discover_with_cancellation(
        &self,
        project_id: &str,
        workspace_root: &Path,
        config: &SkillsConfig,
        cancellation: tokio_util::sync::CancellationToken,
    ) -> Result<SkillsStateSnapshot> {
        self.discover_from_source(
            project_id,
            workspace_root,
            config,
            cancellation,
            DiscoverySource::Local,
        )
        .await
        .map(|(capture, _)| capture.snapshot)
    }

    /// 产品命令的显式发现：同时保留快照与本次发布的捕获证据。
    pub(in crate::studio::runtime) async fn discover_product(
        &self,
        project_id: &str,
        workspace_root: &Path,
        config: &SkillsConfig,
    ) -> Result<SkillsDiscovery> {
        self.discover_from_source(
            project_id,
            workspace_root,
            config,
            tokio_util::sync::CancellationToken::new(),
            DiscoverySource::Local,
        )
        .await
        .map(|(capture, _)| capture)
    }

    /// 远端产品命令的显式发现：与本地发现共用同一快照与发布路径。
    pub(in crate::studio::runtime) async fn discover_remote_product(
        &self,
        project_id: &str,
        workspace_root: &Path,
        config: &SkillsConfig,
        cancellation: tokio_util::sync::CancellationToken,
        remote_backend: Arc<pl_tool::remote::RemoteWorkspaceFileBackend>,
    ) -> Result<SkillsDiscovery> {
        self.discover_from_source(
            project_id,
            workspace_root,
            config,
            cancellation,
            DiscoverySource::Remote(remote_backend),
        )
        .await
        .map(|(capture, _)| capture)
    }

    /// Publishes preparation discovery while keeping the current source capability separate
    /// from any last-good catalog retained by the Settings state machine.
    pub(in crate::studio) async fn prepare_thread_catalog(
        &self,
        project_id: &str,
        workspace_root: &Path,
        config: &SkillsConfig,
        cancellation: tokio_util::sync::CancellationToken,
        remote: Option<Arc<pl_tool::remote::RemoteWorkspaceFileBackend>>,
    ) -> Result<Option<(Arc<FrozenSkillCatalog>, SkillDiscoverySources)>> {
        let source = remote.map_or(DiscoverySource::Local, DiscoverySource::Remote);
        let (snapshot, sources) = self
            .discover_from_source(project_id, workspace_root, config, cancellation, source)
            .await?;
        Ok(snapshot
            .snapshot
            .catalog_for_turn()
            .map(|catalog| (catalog, sources)))
    }

    async fn discover_from_source(
        &self,
        project_id: &str,
        workspace_root: &Path,
        config: &SkillsConfig,
        cancellation: tokio_util::sync::CancellationToken,
        source: DiscoverySource,
    ) -> Result<(SkillsDiscovery, SkillDiscoverySources)> {
        let _command = tokio::select! {
            biased;
            () = cancellation.cancelled() => anyhow::bail!("Skill discovery cancelled"),
            command = self.command_lock.lock() => command,
        };
        let fingerprint = skills_fingerprint(config)?;
        let previous = self.read(project_id).await;
        let revision = previous.state.revision();
        let operation_id = format!("skills-discover-{}", revision.saturating_add(1));
        let running = SkillsStateSnapshot {
            project_id: project_id.to_string(),
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
        self.publish(project_id, running.clone()).await?;

        let workspace_root = workspace_root.to_path_buf();
        let config = config.clone();
        let discovered = match source {
            DiscoverySource::Local => {
                let system_skills_dir = self
                    .system_skills_dir
                    .as_ref()
                    .map(|path| path.as_ref().clone());
                self.registry
                    .discover(SkillProviderRequest {
                        workspace_root,
                        config,
                        system_dir: system_skills_dir,
                        cancellation,
                    })
                    .await
                    .map_err(Error::from)
            }
            DiscoverySource::Remote(remote_backend) => {
                // 系统目录通过 explicit provider 注册，request 不再携带 system_dir。
                let system_skills_dir = self.system_skills_dir();
                let (registry, registrations) = remote::remote_workspace_registry(
                    &config,
                    system_skills_dir.as_deref(),
                    remote_backend,
                )?;
                let discovered = registry
                    .discover(SkillProviderRequest {
                        workspace_root,
                        config,
                        system_dir: None,
                        cancellation,
                    })
                    .await
                    .map_err(Error::from);
                drop(registrations);
                discovered
            }
        };
        let catalog = match discovered {
            Ok(catalog) => catalog,
            Err(error) => {
                let checked_at = unix_seconds();
                let failed = SkillsStateSnapshot {
                    project_id: project_id.to_string(),
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
                self.publish(project_id, failed).await?;
                return Err(error);
            }
        };
        let sources = catalog.discovery_sources();
        let checked_at = unix_seconds();
        if !catalog.snapshot().complete {
            let failed = SkillsStateSnapshot {
                project_id: project_id.to_string(),
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
            let publication = self.publish(project_id, failed.clone()).await?;
            // The incomplete catalog is published as a failed observation and still keeps its
            // exact publication capture and per-source capability available to both callers.
            return Ok((
                SkillsDiscovery {
                    snapshot: failed,
                    publication,
                },
                sources,
            ));
        }
        let catalog_revision = previous.state.value().map_or(1, |data| {
            if catalog_content_eq(data.catalog.snapshot(), catalog.snapshot()) {
                data.catalog_revision
            } else {
                data.catalog_revision.saturating_add(1)
            }
        });
        let snapshot = SkillsStateSnapshot {
            project_id: project_id.to_string(),
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
        let publication = self.publish(project_id, snapshot.clone()).await?;
        Ok((
            SkillsDiscovery {
                snapshot,
                publication,
            },
            sources,
        ))
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
                    if let Some(source) = &self.product_source {
                        // publish retains capture failures in the original product owner/feed.
                        let _capture_result = source.publish(state);
                    }
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

    async fn publish(
        &self,
        project_id: &str,
        snapshot: SkillsStateSnapshot,
    ) -> Result<Option<Arc<super::super::skills::SkillsSnapshot>>> {
        let captured = {
            let mut states = self.states.write().await;
            states.insert(project_id.to_string(), snapshot.clone());
            self.product_source
                .as_ref()
                .map(|source| source.publish(&snapshot))
                .transpose()
        };
        if let Some(events) = &self.events {
            events.emit_skills_state(snapshot);
        }
        Ok(captured?)
    }
}

fn catalog_content_eq(left: &SkillCatalog, right: &SkillCatalog) -> bool {
    left.project_dir == right.project_dir && left.skills == right.skills
}

pub(in crate::studio::runtime) fn skills_fingerprint(config: &SkillsConfig) -> Result<String> {
    let serialized = serde_json::to_vec(config)?;
    let mut hasher = DefaultHasher::new();
    serialized.hash(&mut hasher);
    Ok(format!("{:x}", hasher.finish()))
}

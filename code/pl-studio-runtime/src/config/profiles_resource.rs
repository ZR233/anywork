//! 配置 owner 持有的 canonical Agent Profiles 资源。
//!
//! 启动装载、配置命令与显式重扫采用一次新的目录扫描；查询与订阅只读取已发布
//! 缓存，不扫描文件、不周期轮询（design/18 §18.4）。资源与运行期 Agent directory
//! 是两个领域，互不替代。

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, Weak};

use tokio::sync::watch;

use crate::studio::unix_seconds;
use crate::{
    StudioAgentProfileDiagnostic, StudioAgentProfilesData, StudioAgentProfilesStateSnapshot,
};

use super::profiles_projection::{
    self, ProfilesCaptureFailure, ProfilesMaterial, ProfilesSnapshot, ProfilesSource,
};
use super::runtime::ConfigurationStatusMaterial;
use super::{AgentProfileCatalog, ConfigPaths, StudioConfig};
use pl_protocol::products::identity::ProductReadOrigin;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_protocol::{ObservedResource, ObservedResourceCommand};

/// 已发布的 Agent Profiles 资源事实。
///
/// `catalog` 是完整配置视图（含被禁用的系统与用户 Profile）加逐文件诊断；
/// `revision` 只在目录内容真实变化时前进，空 delta 不提升 revision。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AgentProfilesSnapshot {
    pub revision: u64,
    pub updated_at: i64,
    pub catalog: AgentProfileCatalog,
}

/// canonical Agent Profiles 资源：缓存事实 + 变更唤醒通道。
#[derive(Clone)]
pub struct AgentProfilesResource {
    state: Arc<Mutex<State>>,
    updates: Arc<watch::Sender<u64>>,
}

struct State {
    snapshot: AgentProfilesSnapshot,
    projection_revision: u64,
    next_entity: u64,
    material: Result<Arc<ProfilesMaterial>, Arc<ProfilesCaptureFailure>>,
    status: Result<Arc<ConfigurationStatusMaterial>, Arc<ProfilesCaptureFailure>>,
    last_failure: Option<Arc<ProfilesCaptureFailure>>,
    sources: BTreeMap<String, Weak<ProfilesSource>>,
    closing: bool,
}

/// Exact original adoption evidence; the subsequent call owner must retain this, not a DTO.
#[derive(Clone)]
pub(crate) struct AgentProfilesEvidence {
    pub(crate) snapshot: AgentProfilesSnapshot,
    pub(crate) captures: BTreeMap<String, Result<Arc<ProfilesSnapshot>, StudioError>>,
}

/// Waking observers is separate from canonical capture, including the legacy watch.
pub(crate) struct AgentProfilesPublication {
    pub(crate) evidence: AgentProfilesEvidence,
    sources: Vec<Arc<ProfilesSource>>,
    updates: Arc<watch::Sender<u64>>,
    changed: bool,
}
impl AgentProfilesPublication {
    pub(crate) fn notify(self) {
        if self.changed {
            let revision = self.evidence.snapshot.revision;
            self.updates.send_if_modified(|published| {
                if *published >= revision {
                    false
                } else {
                    *published = revision;
                    true
                }
            });
        }
        for source in self.sources {
            source.notify();
        }
    }
}

impl AgentProfilesResource {
    /// 启动装载：执行一次目录扫描并发布首帧事实（revision 从 0 前进到 1）。
    pub fn new(paths: &ConfigPaths, config: &StudioConfig) -> Self {
        let catalog = AgentProfileCatalog::discover_for_settings(paths, config);
        let at = unix_seconds();
        let mut next_entity = 4;
        let material = profiles_projection::capture(None, catalog.clone(), &mut next_entity);
        let (updates, _) = watch::channel(0);
        Self {
            state: Arc::new(Mutex::new(State {
                snapshot: AgentProfilesSnapshot {
                    revision: 1,
                    updated_at: at,
                    catalog,
                },
                projection_revision: 1,
                next_entity,
                last_failure: material.as_ref().err().cloned(),
                material,
                status: Ok(Arc::new(ConfigurationStatusMaterial::new(
                    1,
                    Arc::new(ObservedResource::ready(1, at, ())),
                ))),
                sources: BTreeMap::new(),
                closing: false,
            })),
            updates: Arc::new(updates),
        }
    }

    /// 读取已发布资源；纯内存克隆，不触发文件系统访问。
    pub fn read(&self) -> AgentProfilesSnapshot {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .snapshot
            .clone()
    }

    /// 订阅资源变更唤醒；通道值为最新 revision。
    pub fn subscribe(&self) -> watch::Receiver<u64> {
        self.updates.subscribe()
    }

    /// 采用一次扫描；内容未变不推进业务水位，原生来源仍观察本次采用的 metadata。
    pub fn adopt_scan(&self, paths: &ConfigPaths, config: &StudioConfig) {
        self.adopt_scan_captured(paths, config).notify();
    }

    pub(crate) fn attach_source(
        &self,
        origin: ProductReadOrigin,
    ) -> Result<Arc<ProfilesSource>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing {
            return Err(StudioError::new(
                StudioErrorCode::Cancelled,
                "Profiles owner is closing",
                false,
            ));
        }
        state.sources.retain(|_, source| source.strong_count() != 0);
        if let Some(source) = state
            .sources
            .get(&origin.owner_epoch)
            .and_then(Weak::upgrade)
        {
            if source.origin() != &origin {
                return Err(StudioError::new(
                    StudioErrorCode::Conflict,
                    "A different Profiles origin is registered for this owner",
                    false,
                ));
            }
            source.ensure_open()?;
            return Ok(source);
        }
        let source = ProfilesSource::new(origin);
        source.publish(snapshot_for(&state, &source), false);
        state
            .sources
            .insert(source.origin().owner_epoch.clone(), Arc::downgrade(&source));
        Ok(source)
    }

    /// Scan only on the original command path; identity/material/status adoption is atomic.
    /// The caller defers `notify` until its command guard is released.
    pub(crate) fn adopt_scan_captured(
        &self,
        paths: &ConfigPaths,
        config: &StudioConfig,
    ) -> AgentProfilesPublication {
        let catalog = AgentProfileCatalog::discover_for_settings(paths, config);
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing {
            return publication(&mut state, self.updates.clone(), false);
        }
        let changed = state.snapshot.catalog != catalog;
        if changed {
            match profiles_projection::next(state.snapshot.revision) {
                Ok(revision) => {
                    let material = match &state.material {
                        Ok(previous) => {
                            let previous = previous.clone();
                            profiles_projection::capture(
                                Some(&previous),
                                catalog.clone(),
                                &mut state.next_entity,
                            )
                        }
                        Err(failure) => Err(failure.clone()),
                    };
                    state.snapshot = AgentProfilesSnapshot {
                        revision,
                        updated_at: unix_seconds(),
                        catalog,
                    };
                    state.material = material;
                }
                Err(failure) => state.material = Err(failure),
            }
        }
        advance_status(&mut state, false);
        publication(&mut state, self.updates.clone(), changed)
    }

    pub(crate) fn stop_captured(&self) -> AgentProfilesPublication {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if !state.closing {
            state.closing = true;
            advance_status(&mut state, true);
        }
        publication(&mut state, self.updates.clone(), false)
    }
}

fn advance_status(state: &mut State, closing: bool) {
    state.status = state
        .status
        .as_ref()
        .map_err(Arc::clone)
        .and_then(|current| {
            let revision = current.metadata().revision();
            let next = profiles_projection::next(revision)?;
            let at = unix_seconds();
            let command = if closing {
                ObservedResourceCommand::Stop {
                    expected_revision: revision,
                    stopped_at: at,
                }
            } else {
                ObservedResourceCommand::Observe {
                    expected_revision: revision,
                    observed_at: at,
                    last_checked_at: None,
                    value: (),
                }
            };
            current
                .metadata()
                .decide(command)
                .map(|decision| {
                    Arc::new(ConfigurationStatusMaterial::new(
                        next,
                        Arc::new(decision.next_state),
                    ))
                })
                .map_err(|error| {
                    ProfilesCaptureFailure::new(StudioError::new(
                        StudioErrorCode::Protocol,
                        format!("Profiles source metadata transition failed: {error}"),
                        false,
                    ))
                })
        });
    match profiles_projection::next(state.projection_revision) {
        Ok(revision) => state.projection_revision = revision,
        Err(failure) => state.material = Err(failure),
    }
    state.last_failure = state
        .status
        .as_ref()
        .err()
        .cloned()
        .or_else(|| state.material.as_ref().err().cloned())
        .or_else(|| state.last_failure.clone());
}
fn snapshot_for(state: &State, source: &ProfilesSource) -> Arc<ProfilesSnapshot> {
    Arc::new(ProfilesSnapshot {
        origin: source.origin().clone(),
        revision: state.projection_revision,
        profiles_revision: state.snapshot.revision,
        source_status: state.status.clone(),
        material: state.material.clone(),
        last_failure: state.last_failure.clone(),
    })
}
fn publication(
    state: &mut State,
    updates: Arc<watch::Sender<u64>>,
    changed: bool,
) -> AgentProfilesPublication {
    state.sources.retain(|_, source| source.strong_count() != 0);
    let sources: Vec<_> = state.sources.values().filter_map(Weak::upgrade).collect();
    let captures = sources
        .iter()
        .map(|source| {
            let snapshot = snapshot_for(state, source);
            let captured = if state.closing {
                Err(StudioError::new(
                    StudioErrorCode::Cancelled,
                    "Profiles owner is closing",
                    false,
                ))
            } else {
                Ok(snapshot.clone())
            };
            source.publish(snapshot, state.closing);
            (source.origin().owner_epoch.clone(), captured)
        })
        .collect();
    AgentProfilesPublication {
        evidence: AgentProfilesEvidence {
            snapshot: state.snapshot.clone(),
            captures,
        },
        sources,
        updates,
        changed,
    }
}

impl From<AgentProfilesSnapshot> for StudioAgentProfilesStateSnapshot {
    fn from(snapshot: AgentProfilesSnapshot) -> Self {
        Self {
            state: pl_protocol::ObservedResource::ready(
                snapshot.revision,
                snapshot.updated_at,
                StudioAgentProfilesData {
                    profiles: snapshot.catalog.profiles,
                    diagnostics: snapshot
                        .catalog
                        .diagnostics
                        .into_iter()
                        .map(|diagnostic| StudioAgentProfileDiagnostic {
                            path: diagnostic.path.to_string_lossy().into_owned(),
                            message: diagnostic.message,
                        })
                        .collect(),
                },
            ),
        }
    }
}

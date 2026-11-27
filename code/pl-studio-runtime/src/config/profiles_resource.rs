//! 配置 owner 持有的 canonical Agent Profiles 资源。
//!
//! 启动装载、配置命令与显式重扫采用一次新的目录扫描；查询与订阅只读取已发布
//! 缓存，不扫描文件、不周期轮询（design/18 §18.4）。资源与运行期 Agent directory
//! 是两个领域，互不替代。

use tokio::sync::watch;

use crate::studio::unix_seconds;
use crate::{
    StudioAgentProfileDiagnostic, StudioAgentProfilesData, StudioAgentProfilesStateSnapshot,
};

use super::agent_profile::NativeProfileCheck;
use super::fs_util::{RevisionedState, WatchedResource};
use super::{AgentProfileCatalog, ConfigPaths, StudioConfig};

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

impl RevisionedState for AgentProfilesSnapshot {
    fn revision(&self) -> u64 {
        self.revision
    }

    fn revision_mut(&mut self) -> &mut u64 {
        &mut self.revision
    }
}

/// canonical Agent Profiles 资源：缓存事实 + 变更唤醒通道。
///
/// 订阅通道的初始值就是已发布快照的 `revision`，首帧之后只有在目录内容真实变化时
/// 才推进 revision 并通知观察者。
#[derive(Clone)]
pub struct AgentProfilesResource {
    resource: WatchedResource<AgentProfilesSnapshot>,
    native_check: NativeProfileCheck,
}

impl AgentProfilesResource {
    /// 启动装载：执行一次目录扫描并发布首帧事实（revision 从 0 前进到 1）。
    pub fn new(
        paths: &ConfigPaths,
        config: &StudioConfig,
        acp: &super::AcpDefinitionsSnapshot,
    ) -> Self {
        Self::with_native_check(paths, config, acp, NativeProfileCheck::OnScan)
    }

    pub(super) fn with_native_check(
        paths: &ConfigPaths,
        config: &StudioConfig,
        acp: &super::AcpDefinitionsSnapshot,
        native_check: NativeProfileCheck,
    ) -> Self {
        let catalog =
            AgentProfileCatalog::discover_for_settings_with_check(paths, config, acp, native_check);
        Self {
            resource: WatchedResource::new(AgentProfilesSnapshot {
                revision: 1,
                updated_at: unix_seconds(),
                catalog,
            }),
            native_check,
        }
    }

    /// 读取已发布资源；纯内存克隆，不触发文件系统访问。
    pub fn read(&self) -> AgentProfilesSnapshot {
        self.resource.read()
    }

    /// 订阅资源变更唤醒；通道值为最新 revision。
    pub fn subscribe(&self) -> watch::Receiver<u64> {
        self.resource.subscribe()
    }

    /// 采用一次新的目录扫描；目录未变化时不提升 revision、不通知观察者。
    pub fn adopt_scan(
        &self,
        paths: &ConfigPaths,
        config: &StudioConfig,
        acp: &super::AcpDefinitionsSnapshot,
    ) {
        let catalog = AgentProfileCatalog::discover_for_settings_with_check(
            paths,
            config,
            acp,
            self.native_check,
        );
        self.resource.publish(|state| {
            if state.catalog == catalog {
                return false;
            }
            state.updated_at = unix_seconds();
            state.catalog = catalog;
            true
        });
    }
}

impl From<AgentProfilesSnapshot> for StudioAgentProfilesStateSnapshot {
    fn from(snapshot: AgentProfilesSnapshot) -> Self {
        Self {
            state: crate::ObservedResource::ready(
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

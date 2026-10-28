//! typed 产品 topic 订阅：登记接收者、读取领域基线与帧交付。

use anyhow::Result;
use std::sync::Arc;
use tokio::sync::broadcast;

use crate::{
    StudioProductBaseline, StudioProductBaselineState, StudioProductFrame, StudioProductTopic,
};

use super::StudioRuntime;

const BASELINE_THREAD_PAGE_LIMIT: usize = 50;

/// 一个 typed 产品 topic 订阅句柄。
///
/// 订阅在构造时先登记 topic 接收者，再读取该领域 canonical 基线；`recv` 首帧返回
/// 基线，之后只交付该领域事件。全局 `sequence` 允许不连续，只有
/// [`StudioProductFrame::Lagged`] 表示无法证明连续，需要仅重读该 topic 的基线。查询不
/// activation、不扫描、不 mutation；订阅本身不创建新的 owner。
pub struct StudioProductTopicSubscription {
    topic: StudioProductTopic,
    receiver: broadcast::Receiver<crate::StudioProductEventEnvelope>,
    baseline: Option<StudioProductBaseline>,
    /// 活跃会话费用订阅持有的原 root 观察需求；与本订阅同生命周期释放。
    ///
    /// 只借用既有计费所有者：不创建或激活会话执行 owner。最后一份需求消失后，没有费用材料
    /// 的空观察条目可被回收。
    _session_costs_lease: Option<Arc<()>>,
}

impl StudioProductTopicSubscription {
    /// 订阅的 topic。
    pub fn topic(&self) -> &StudioProductTopic {
        &self.topic
    }

    /// 交付下一帧：首帧为基线，其后为该领域事件；`None` 表示通道已关闭。
    pub async fn recv(&mut self) -> Result<Option<StudioProductFrame>> {
        if let Some(baseline) = self.baseline.take() {
            return Ok(Some(StudioProductFrame::Baseline(Box::new(baseline))));
        }
        match self.receiver.recv().await {
            Ok(event) => Ok(Some(StudioProductFrame::Event(Box::new(event)))),
            Err(broadcast::error::RecvError::Lagged(dropped)) => {
                Ok(Some(StudioProductFrame::Lagged {
                    topic: self.topic.clone(),
                    dropped,
                }))
            }
            Err(broadcast::error::RecvError::Closed) => Ok(None),
        }
    }
}

impl StudioRuntime {
    /// 订阅一个 typed 产品 topic。
    ///
    /// 先登记接收者再读取基线：登记与基线之间发布的事件仍留在通道缓冲里，消费端按
    /// payload 的领域 revision 合并，旧基线不会覆盖较新事件。带作用域 topic 的身份
    /// 为空时返回类型化错误。
    pub async fn subscribe_product_topic(
        &self,
        topic: StudioProductTopic,
    ) -> Result<StudioProductTopicSubscription> {
        topic.validate()?;
        let receiver = self.agent_facility.product_events.subscribe_topic(&topic);
        // 活跃会话费用订阅必须先登记原 root 观察需求，再取与该登记同一边界的基线；其余 topic
        // 保持原有的"先登记接收者、再读纯查询基线"顺序。
        let (baseline, session_costs_lease) = match &topic {
            StudioProductTopic::SessionCosts { root_thread_id } => {
                let observation = self
                    .observe_session_costs_subscription(root_thread_id)
                    .await?;
                (
                    product_baseline(
                        &topic,
                        StudioProductBaselineState::SessionCosts(Box::new(observation.baseline)),
                    ),
                    Some(observation.lease),
                )
            }
            _ => (self.read_product_baseline(&topic).await?, None),
        };
        Ok(StudioProductTopicSubscription {
            topic,
            receiver,
            baseline: Some(baseline),
            _session_costs_lease: session_costs_lease,
        })
    }

    /// 读取一个 topic 的当前 canonical 基线；纯查询，不产生副作用。
    pub async fn read_product_baseline(
        &self,
        topic: &StudioProductTopic,
    ) -> Result<StudioProductBaseline> {
        topic.validate()?;
        let state = match topic {
            StudioProductTopic::ProjectDirectory => {
                StudioProductBaselineState::ProjectDirectory(Box::new(
                    self.agent_facility
                        .product_events
                        .read_project_directory()
                        .await?,
                ))
            }
            StudioProductTopic::ThreadDirectory => {
                StudioProductBaselineState::ThreadDirectory(Box::new(
                    self.agent_facility
                        .product_events
                        .read_thread_directory_page(None, BASELINE_THREAD_PAGE_LIMIT)
                        .await?,
                ))
            }
            StudioProductTopic::AgentDirectory => {
                StudioProductBaselineState::AgentDirectory(Box::new(
                    self.agent_facility
                        .product_events
                        .read_agent_directory()
                        .await,
                ))
            }
            StudioProductTopic::SettingsConfig => StudioProductBaselineState::SettingsConfig(
                Box::new(self.read_settings_config_state()?),
            ),
            StudioProductTopic::ModelCatalog => {
                let (settings, catalog_state) = self.config_runtime.read_with_catalog()?;
                let catalog =
                    super::settings_api::model_catalog_snapshot(&settings, &catalog_state)?;
                StudioProductBaselineState::ModelCatalog(Box::new(
                    crate::StudioModelCatalogStateSnapshot {
                        state: pl_protocol::ObservedResource::ready(
                            catalog.revision,
                            catalog.updated_at,
                            catalog,
                        ),
                    },
                ))
            }
            StudioProductTopic::Mcp => {
                StudioProductBaselineState::Mcp(Box::new(self.read_mcp_state().await?))
            }
            StudioProductTopic::Lsp => {
                StudioProductBaselineState::Lsp(Box::new(self.read_lsp_state().await))
            }
            StudioProductTopic::Skills { project_id } => StudioProductBaselineState::Skills(
                Box::new(self.read_skills_state(project_id).await),
            ),
            StudioProductTopic::ThreadModeCatalog => StudioProductBaselineState::ThreadModeCatalog(
                Box::new(self.read_thread_mode_catalog()),
            ),
            StudioProductTopic::AccountUsage => StudioProductBaselineState::AccountUsage(Box::new(
                self.read_account_usage_state().await,
            )),
            StudioProductTopic::AcpAuth => {
                StudioProductBaselineState::AcpAuth(Box::new(self.acp_auth.read_state()))
            }
            StudioProductTopic::AcpInstall => {
                StudioProductBaselineState::AcpInstall(Box::new(self.acp_install.read_state()))
            }
            StudioProductTopic::ModelPerformance => StudioProductBaselineState::ModelPerformance(
                Box::new(self.model_performance.snapshot().await),
            ),
            StudioProductTopic::SessionCosts { root_thread_id } => {
                StudioProductBaselineState::SessionCosts(Box::new(
                    self.model_performance
                        .session_costs_snapshot(root_thread_id)
                        .await,
                ))
            }
            StudioProductTopic::Updater => {
                StudioProductBaselineState::Updater(Box::new(self.read_update_state().await))
            }
            StudioProductTopic::Persistence => StudioProductBaselineState::Persistence(Box::new(
                self.agent_facility.product_events.persistence_state(),
            )),
            StudioProductTopic::PersistenceQueue => StudioProductBaselineState::PersistenceQueue(
                Box::new(self.agent_facility.product_events.persistence_queue_state()),
            ),
            StudioProductTopic::AgentProfiles => StudioProductBaselineState::AgentProfiles(
                Box::new(self.read_agent_profiles_state()?),
            ),
            StudioProductTopic::Bots => {
                StudioProductBaselineState::Bots(Box::new(self.bots.snapshot().await))
            }
        };
        Ok(product_baseline(topic, state))
    }
}

/// 领域基线载体；`revision` 只来自该领域载荷自身。
fn product_baseline(
    topic: &StudioProductTopic,
    state: StudioProductBaselineState,
) -> StudioProductBaseline {
    StudioProductBaseline {
        topic: topic.clone(),
        revision: state.revision(),
        state,
    }
}

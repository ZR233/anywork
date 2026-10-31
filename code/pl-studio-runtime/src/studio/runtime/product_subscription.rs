//! typed 产品 topic 订阅：登记接收者、读取领域基线与帧交付。

use anyhow::Result;
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
        let baseline = self.read_product_baseline(&topic).await?;
        Ok(StudioProductTopicSubscription {
            topic,
            receiver,
            baseline: Some(baseline),
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
            StudioProductTopic::Recovery => {
                StudioProductBaselineState::Recovery(Box::new(crate::StudioRecoveryStateSnapshot {
                    state: self.recovery.state(),
                }))
            }
            StudioProductTopic::Mcp => {
                StudioProductBaselineState::Mcp(Box::new(self.read_mcp_state().await?))
            }
            StudioProductTopic::Lsp => {
                StudioProductBaselineState::Lsp(Box::new(self.read_lsp_state().await))
            }
            StudioProductTopic::Skills { workspace_id } => StudioProductBaselineState::Skills(
                Box::new(self.read_skills_state(workspace_id).await),
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
            StudioProductTopic::ChildInteractions { host_thread_id } => {
                self.ensure_root_host(host_thread_id).await?;
                StudioProductBaselineState::ChildInteractions(Box::new(
                    self.agent_facility
                        .product_events
                        .read_child_interactions_state(host_thread_id),
                ))
            }
        };
        let revision = state.revision();
        Ok(StudioProductBaseline {
            topic: topic.clone(),
            revision,
            state,
        })
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;
    use std::sync::Arc;

    use anyhow::{Context, Result};
    use pl_core::context::OpaquePayload;
    use pl_core::thread::interactions::{
        InteractionRecord, InteractionRequest, InteractionResponse, InteractionState,
    };
    use pl_core::thread::permissions::{PermissionRecord, PermissionState};
    use pl_core::thread::{ThreadLifecycle, ThreadSnapshot};
    use pl_protocol::{MessagePresentation, UserInputAnswer, UserInputResolution, UserQuestion};
    use tokio::sync::Barrier;

    use super::*;
    use crate::studio::store::directory::DirectoryDelta;
    use crate::{StudioHostKind, StudioProductEventKind, StudioRuntimeOptions};

    #[tokio::test]
    async fn child_interactions_topic_tracks_projection_without_activating_child() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
            studio_home: Some(home),
            host: StudioHostKind::Test,
            ..StudioRuntimeOptions::desktop()
        })
        .await?;
        let project = runtime.open_project(&workspace).await?;
        let (root_delta, root) = DirectoryDelta::register_root_thread(
            "interaction-root".into(),
            &project.id,
            "root",
            pl_protocol::ThreadModeId::simple(),
            pl_protocol::ThreadWorkspaceMode::Local,
            workspace.to_string_lossy().into_owned(),
        );
        runtime
            .agent_facility
            .product_events
            .commit_directory(root_delta)
            .await?;
        let topic = StudioProductTopic::ChildInteractions {
            host_thread_id: root.id.clone(),
        };
        let mut subscription = runtime.subscribe_product_topic(topic.clone()).await?;
        let empty = baseline_state(subscription.recv().await?)?;
        assert_eq!(empty.host_thread_id, root.id);
        assert_eq!(empty.state.revision(), 1);
        assert!(
            empty
                .state
                .value()
                .context("ready empty baseline")?
                .is_empty()
        );

        let mut child = root.clone();
        child.id = "interaction-child".into();
        child.root_thread_id = root.id.clone();
        child.parent_thread_id = Some(root.id.clone());
        child.agent_path = format!("{}/{}", root.id, child.id);
        child.role = "executor".into();
        runtime
            .agent_facility
            .product_events
            .commit_directory(DirectoryDelta {
                thread_upserts: vec![child.clone()],
                ..Default::default()
            })
            .await?;
        assert!(runtime.threads.thread(&child.id).is_none());
        assert!(
            runtime
                .read_product_baseline(&StudioProductTopic::ChildInteractions {
                    host_thread_id: child.id.clone(),
                })
                .await
                .is_err(),
            "a child cannot masquerade as an interaction host"
        );
        assert!(
            StudioProductTopic::ChildInteractions {
                host_thread_id: " ".into()
            }
            .validate()
            .is_err()
        );

        let mut pending = ThreadSnapshot {
            commit_sequence: 1,
            lifecycle: ThreadLifecycle::Open,
            ..Default::default()
        };
        pending.interactions.insert(
            "question".into(),
            question_record(InteractionState::Pending, 1)?,
        );
        pending.interactions.insert("plan".into(), plan_record()?);
        pending
            .permissions
            .insert("approval".into(), permission_record()?);
        runtime
            .agent_facility
            .product_events
            .update_child_interactions(&child, &pending)?
            .context("pending collection change")?;
        let published = event_state(subscription.recv().await?)?;
        let pending_interactions = published.state.value().context("pending event")?;
        assert_eq!(pending_interactions.len(), 2);
        assert!(
            pending_interactions
                .iter()
                .all(|interaction| interaction.child_thread_id == child.id)
        );
        assert!(
            pending_interactions
                .iter()
                .any(|interaction| interaction.kind == pl_protocol::InteractionKind::UserInput)
        );
        assert!(
            pending_interactions.iter().any(|interaction| {
                interaction.kind == pl_protocol::InteractionKind::ToolApproval
            })
        );
        assert!(runtime.threads.thread(&child.id).is_none());

        let nonempty = baseline_state(
            runtime
                .subscribe_product_topic(topic.clone())
                .await?
                .recv()
                .await?,
        )?;
        assert_eq!(nonempty.state.value().context("ready baseline")?.len(), 2);
        assert_eq!(nonempty.state.revision(), published.state.revision());

        let mut resolved = pending.clone();
        resolved.commit_sequence = 2;
        resolved
            .interactions
            .insert("question".into(), question_record(resolved_state()?, 2)?);
        resolved.permissions.clear();
        runtime
            .agent_facility
            .product_events
            .update_child_interactions(&child, &resolved)?
            .context("decision removes pending interaction")?;
        let decided = event_state(subscription.recv().await?)?;
        assert!(decided.state.value().context("decision event")?.is_empty());

        let mut pending_again = pending.clone();
        pending_again.commit_sequence = 3;
        runtime
            .agent_facility
            .product_events
            .update_child_interactions(&child, &pending_again)?
            .context("new pending interaction")?;
        let republished = event_state(subscription.recv().await?)?;
        assert_eq!(republished.state.value().context("pending again")?.len(), 2);

        let barrier = Arc::new(Barrier::new(3));
        let bus = runtime.agent_facility.product_events.clone();
        let newer_child = child.clone();
        let mut newer = resolved.clone();
        newer.commit_sequence = 4;
        let newer_barrier = barrier.clone();
        let newer_task = tokio::spawn(async move {
            newer_barrier.wait().await;
            bus.update_child_interactions(&newer_child, &newer)
        });
        let bus = runtime.agent_facility.product_events.clone();
        let stale_child = child.clone();
        let stale = resolved.clone();
        let stale_barrier = barrier.clone();
        let stale_task = tokio::spawn(async move {
            stale_barrier.wait().await;
            bus.update_child_interactions(&stale_child, &stale)
        });
        barrier.wait().await;
        assert!(newer_task.await??.is_some());
        assert!(stale_task.await??.is_none());
        let current = runtime.read_product_baseline(&topic).await?;
        let StudioProductBaselineState::ChildInteractions(current) = current.state else {
            unreachable!("child interaction baseline")
        };
        assert!(
            current
                .state
                .value()
                .context("current projection")?
                .is_empty()
        );
        let raced = event_state(subscription.recv().await?)?;
        assert!(raced.state.value().context("raced event")?.is_empty());

        let mut removable = pending.clone();
        removable.commit_sequence = 5;
        runtime
            .agent_facility
            .product_events
            .update_child_interactions(&child, &removable)?
            .context("pending interaction before archive")?;
        let _ = event_state(subscription.recv().await?)?;
        runtime
            .agent_facility
            .product_events
            .commit_directory(DirectoryDelta::archive_threads(vec![child.id.clone()]))
            .await?;
        let removed = event_state(subscription.recv().await?)?;
        assert!(removed.state.value().context("archive event")?.is_empty());
        assert!(removed.state.revision() > republished.state.revision());
        assert!(runtime.threads.thread(&child.id).is_none());

        runtime
            .agent_facility
            .product_events
            .commit_directory(DirectoryDelta {
                thread_upserts: vec![child.clone()],
                ..Default::default()
            })
            .await?;
        let mut before_root_archive = pending;
        before_root_archive.commit_sequence = 6;
        runtime
            .agent_facility
            .product_events
            .update_child_interactions(&child, &before_root_archive)?
            .context("restored child pending interaction")?;
        let restored = event_state(subscription.recv().await?)?;
        runtime
            .agent_facility
            .product_events
            .commit_directory(DirectoryDelta::archive_threads(vec![
                root.id.clone(),
                child.id.clone(),
            ]))
            .await?;
        let root_archived = event_state(subscription.recv().await?)?;
        assert!(
            root_archived
                .state
                .value()
                .context("root archive event")?
                .is_empty()
        );
        assert!(root_archived.state.revision() > restored.state.revision());
        let retained = runtime
            .agent_facility
            .product_events
            .read_child_interactions_state(&root.id);
        assert_eq!(retained.state.revision(), root_archived.state.revision());

        runtime.shutdown_runtime().await?;
        Ok(())
    }

    fn baseline_state(
        frame: Option<StudioProductFrame>,
    ) -> Result<crate::StudioChildInteractionsState> {
        let StudioProductFrame::Baseline(baseline) = frame.context("missing baseline")? else {
            anyhow::bail!("expected baseline frame")
        };
        let StudioProductBaselineState::ChildInteractions(state) = baseline.state else {
            anyhow::bail!("expected child interaction baseline")
        };
        Ok(*state)
    }

    fn event_state(
        frame: Option<StudioProductFrame>,
    ) -> Result<crate::StudioChildInteractionsState> {
        let StudioProductFrame::Event(event) = frame.context("missing event")? else {
            anyhow::bail!("expected event frame")
        };
        let StudioProductEventKind::ChildInteractionsChanged(state) = event.kind else {
            anyhow::bail!("expected child interaction event")
        };
        Ok(state)
    }

    fn question_record(state: InteractionState, revision: u64) -> Result<InteractionRecord> {
        let questions = vec![UserQuestion {
            id: "provider".into(),
            header: "Provider".into(),
            question: "Which provider should be used?".into(),
            is_other: true,
            is_secret: false,
            options: None,
        }];
        Ok(InteractionRecord {
            created_at: 10,
            updated_at: 10 + i64::try_from(revision)?,
            continuation_id: None,
            request: InteractionRequest {
                id: "question".into(),
                turn_id: "turn-question".into(),
                payload: OpaquePayload::new(
                    "pl.tool.user-input",
                    1,
                    serde_json::to_string(&questions)?,
                )?,
            },
            revision,
            state,
            extension_mutations: Vec::new(),
        })
    }

    fn resolved_state() -> Result<InteractionState> {
        let resolution = UserInputResolution {
            answers: HashMap::from([(
                "provider".into(),
                UserInputAnswer {
                    answers: vec!["DeepSeek".into()],
                },
            )]),
        };
        Ok(InteractionState::Resolved(InteractionResponse {
            payload: OpaquePayload::new(
                "pl.studio.user-answer",
                1,
                serde_json::to_string(&resolution)?,
            )?,
            context: Vec::new(),
        }))
    }

    fn plan_record() -> Result<InteractionRecord> {
        let plan = "Verify the root-scoped projection.";
        let prompt = crate::plan_tool::PlanConfirmationPrompt {
            question: UserQuestion {
                id: pl_protocol::AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID.into(),
                header: "Plan".into(),
                question: plan.into(),
                is_other: true,
                is_secret: false,
                options: None,
            },
            expected_plan_revision: 1,
            plan_hash: pl_core::context::content_hash(plan.as_bytes()),
            document_version: None,
            created_at: 10,
            presentation: MessagePresentation::Hidden,
        };
        Ok(InteractionRecord {
            created_at: 10,
            updated_at: 10,
            continuation_id: None,
            request: InteractionRequest {
                id: "plan".into(),
                turn_id: "turn-plan".into(),
                payload: OpaquePayload::new(
                    crate::plan_tool::PLAN_CONFIRMATION_FORMAT,
                    1,
                    serde_json::to_string(&prompt)?,
                )?,
            },
            revision: 1,
            state: InteractionState::Pending,
            extension_mutations: Vec::new(),
        })
    }

    fn permission_record() -> Result<PermissionRecord> {
        let arguments = OpaquePayload::new("pl.tool.input", 1, r#"{"path":"/outside"}"#)?;
        Ok(PermissionRecord {
            created_at: 10,
            updated_at: 10,
            response: None,
            id: "approval".into(),
            task_id: "task-approval".into(),
            call_id: "call-approval".into(),
            turn_id: "turn-approval".into(),
            tool_id: "exec".into(),
            revision: 1,
            payload: OpaquePayload::new(
                "pl.studio.tool-approval",
                1,
                serde_json::to_string(&serde_json::json!({
                    "name": "exec",
                    "arguments": arguments,
                    "workingDirectory": "/workspace",
                }))?,
            )?,
            state: PermissionState::Pending,
        })
    }
}

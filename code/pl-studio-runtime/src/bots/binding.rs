// Explicit and inbound Thread binding share the same durable ledger.
use super::InboundWorkOutcome;
use super::SendAuthority;
use super::occupancy::{OccupancyBudget, projection_freeze_bytes, studio_title_bytes};
use super::owner::{BotRuntime, ManagedBot};
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::reply::{binding_failure, recoverable};
use super::storage::FrozenInbound;
use crate::protocol::*;
use crate::studio::StudioRuntime;
use std::sync::Arc;

/// 创建调用链中“创建身份”文本的 job 持有副本峰值。
///
/// `create_thread_with_id` 的现有边界（`studio/runtime/thread_service`, `studio/store`,
/// `studio/product_event_bus`）：
/// - `register_root_thread` 返回的 Thread 同时持有 `root_thread_id`/`agent_path`/`id` 三份；
/// - `commit_directory` 的 delta 持有该 Thread 的克隆（3 份），并在跨
///   `apply_project_delta().await` 期间与本任务手里的那份 Thread（3 份）、
///   `publish_thread_delta` 放入 envelope 的 upserted Thread（3 份）同时存活；
/// - 本任务自己持有创建身份 1 份。
///
/// 合计 10。已明确交接给独立 owner、不再由本任务持有的副本：`record_directory(delta.clone())`
/// 进入写后队列，`thread_index.insert(thread.clone(), …)` 进入目录 owner，
/// `persist_directory_summaries` 的 catalog/workspace 镜像归 store owner。
const CREATE_CALL_CREATION_COPIES: usize = 10;

/// 占用区内冻结的输入。联网与凭据的只读权限核验已在占用区之前完成，
/// 任务内只做本地 Thread 创建与绑定接续，不重新获取 secret 或 token。
/// 只保留身份/标题/操作所需标量：不捕获整份配置、可信集合或 secret。
struct FrozenBinding {
    runtime: Arc<crate::studio::StudioRuntime>,
    managed: Arc<ManagedBot>,
    bot_id: String,
    chat_id: String,
    workspace_id: String,
    /// 本地 Thread 标题在进入占用区之前预生成，写入后不再临时派生。
    title: String,
    app_id: String,
    operation_id: String,
    content_hash: String,
    creation_id: String,
    owner_epoch: String,
    expected_config_revision: u64,
    expected_binding_revision: u64,
}

impl FrozenBinding {
    /// 按 UTF-8 字节数受检计权，供占用 owner 的任务/文本双预算使用。
    ///
    /// 副本峰值按占用任务内各持久 await 阶段列出（首写是 `begin/adopt_binding_operation`）：
    ///
    /// | 阶段 | operationId/bot/chat/hash | project |
    /// | --- | --- | --- |
    /// | `insert_binding_operation` 的 INSERT 参数 | 3（冻结+操作记录+SQL 参数） | 2（读行+SQL 参数） |
    /// | `bind_thread` 的 UPSERT 参数 | 3（冻结+读行+SQL 参数） | 3（冻结+读行+SQL 参数） |
    /// | `save_binding_operation` 的 INSERT 参数 | 3（冻结+最终记录+SQL 参数） | 1 |
    ///
    /// 标题：本任务 1 份全量 + Studio 目录 3 个 Thread 实例（`register_root_thread`、
    /// `commit_directory` 的 delta 克隆与 envelope、`ThreadRecord`）的 `non_empty_title`
    /// 副本；后者按 trim 后前 80 字符计。Studio 侧索引/写后队列的副本已交接给目录 owner。
    /// app/owner_epoch 只参与比较，各 1 份。创建身份由任务在首次持久写之前单独预留：
    /// 进入 job 时先计 1 份，写前补足调用链峰值（见 `CREATE_CALL_CREATION_COPIES`）。
    fn text_bytes(&self) -> Result<usize, FeishuError> {
        let base = super::occupancy::counted_text_bytes([
            (self.operation_id.as_str(), 3),
            (self.bot_id.as_str(), 3),
            (self.chat_id.as_str(), 3),
            (self.content_hash.as_str(), 3),
            (self.workspace_id.as_str(), 5),
            (self.app_id.as_str(), 1),
            (self.owner_epoch.as_str(), 1),
            (self.title.as_str(), 1),
        ])?;
        super::occupancy::counted_extra_bytes(
            base,
            [
                (self.creation_id.len(), 1),
                (studio_title_bytes(&self.title), 3),
            ],
        )
    }
}

impl BotRuntime {
    pub(super) async fn conversation_binding(
        &self,
        managed: &ManagedBot,
        bot_id: &str,
        workspace_id: &str,
        chat_id: &str,
    ) -> Result<BotConversationThreadBinding, FeishuError> {
        let projection = managed
            .store
            .binding_for_chat(chat_id, bot_id, workspace_id)
            .await?;
        Ok(product_binding(bot_id, workspace_id, projection))
    }

    pub async fn create_conversation_thread(
        &self,
        request: CreateBotConversationThreadRequest,
        owner_epoch: &str,
    ) -> Result<BotConversationThreadReply, FeishuError> {
        let CreateBotConversationThreadRequest {
            operation_id,
            bot_id,
            chat_id,
            expected_config_revision,
            expected_binding_revision,
        } = request;
        let managed = self.managed(&bot_id).await?;
        let content_hash = super::protocol::im::content_hash(
            &operation_id,
            &chat_id,
            &format!("{expected_binding_revision}"),
        );
        let creation_id = format!("botthread:{bot_id}:{chat_id}:{operation_id}");
        // 已持久受理的同一操作先以本地指纹识别：身份一致即继续原创建，不重复目录
        // 核验，也不让已接纳意图卡在联网或 keyring 准备上；输入不同必须显式拒绝。
        let accepted = match managed.store.load_binding_operation(&operation_id).await? {
            Some(existing) => {
                if !binding_operation_matches(
                    &existing,
                    &operation_id,
                    &bot_id,
                    &chat_id,
                    &content_hash,
                    expected_binding_revision,
                ) {
                    return Err(FeishuError::new(
                        FeishuErrorKind::Conflict,
                        "operationId already used with different conversation Thread input",
                        false,
                        None,
                    ));
                }
                true
            }
            None => false,
        };
        // 首次受理才做联网可见性核验与过期 revision 快速拒绝；最终裁决仍在准入内。
        // 接续路径只读取所需标量，不搬运整份配置与可信集合。
        let (name, app_id, workspace_id) = if accepted {
            let current = managed.config.lock().await;
            (
                current.name.clone(),
                current.feishu().app_id.clone(),
                current.workspace_id.clone(),
            )
        } else {
            let config = managed.config.lock().await.clone();
            if config.config_revision != expected_config_revision {
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "stale bot config revision",
                    true,
                    None,
                ));
            }
            let membership = self
                .prepare_chat_access(&managed, &config, &chat_id)
                .await?;
            self.authorize_chat(&config, SendAuthority::Owner, &membership)?;
            (
                config.name.clone(),
                config.feishu().app_id.clone(),
                config.workspace_id.clone(),
            )
        };
        // 标题与操作字段都在此预生成并计入冻结预算：首次持久写前就能判定是否放得下。
        let title = format!("{name} / {chat_id}");
        let Some(runtime) = self.studio_host() else {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "studio runtime host is unavailable",
                true,
                None,
            ));
        };
        // 首次意图的联网可见性与凭据核验已在占用区之前完成；已受理接续不重复核验，
        // 最终身份裁决仍在准入内。本地 Thread 创建与绑定接续由受管占用任务持有到真实
        // 终态，调用方取消只是不再等待回执。
        let worker = self.clone();
        let frozen = FrozenBinding {
            runtime,
            managed,
            bot_id,
            chat_id,
            workspace_id,
            title,
            app_id,
            operation_id,
            content_hash,
            creation_id,
            owner_epoch: owner_epoch.to_string(),
            expected_config_revision,
            expected_binding_revision,
        };
        let text_bytes = frozen.text_bytes()?;
        self.submit_occupancy(text_bytes, move |budget| async move {
            worker.create_binding_thread(frozen, budget).await
        })
        .await
    }

    /// 占用区内的本地创建与绑定接续；只在受管占用任务中运行。
    async fn create_binding_thread(
        &self,
        frozen: FrozenBinding,
        mut budget: OccupancyBudget,
    ) -> Result<BotConversationThreadReply, FeishuError> {
        let FrozenBinding {
            runtime,
            managed,
            bot_id,
            chat_id,
            workspace_id,
            title,
            app_id,
            operation_id,
            content_hash,
            creation_id,
            owner_epoch,
            expected_config_revision,
            expected_binding_revision,
        } = frozen;
        let frozen_creation = {
            let _admission = managed.admission.lock().await;
            self.reject_closed_admission(&managed)?;
            // 身份判据在权威准入内重新核对：占用前的快速检查与联网核验都不能代替它。
            // 只做比较并取回水位标量：不克隆整份配置，也不把 guard 持到 DB await 之后。
            let (identity_ok, current_revision) = {
                let current = managed.config.lock().await;
                (
                    current.feishu().app_id == app_id && current.workspace_id == workspace_id,
                    current.config_revision,
                )
            };
            if !identity_ok {
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "bot identity changed before conversation Thread bind",
                    true,
                    None,
                ));
            }
            // 操作记录只在确认是首次受理后才构造：接续路径不为它保留额外副本。
            if let Some(existing) = managed.store.load_binding_operation(&operation_id).await? {
                if !binding_operation_matches(
                    &existing,
                    &operation_id,
                    &bot_id,
                    &chat_id,
                    &content_hash,
                    expected_binding_revision,
                ) {
                    return Err(FeishuError::new(
                        FeishuErrorKind::Conflict,
                        "operationId already used with different conversation Thread input",
                        false,
                        None,
                    ));
                }
                // 身份核验后只保留真正需要的已存字段，其余读出的 owned 值随解构释放，
                // 并在下一个 await 之前按实际保留长度计权。
                let super::storage::BindingOperation {
                    creation_id: existing_creation,
                    thread_id: existing_thread,
                    ..
                } = existing;
                if let Some(existing_thread) = existing_thread {
                    // 已完成操作：只保留 A 的创建身份与 Thread 身份，各按 1 份跨读取等待。
                    budget.reserve_more(super::occupancy::counted_text_bytes([
                        (existing_creation.as_str(), 1),
                        (existing_thread.as_str(), 1),
                    ])?)?;
                    // 在同一准入内读取当前权威投影：只有仍精确指向 A 的完成结果才算
                    // NoChange；被后继显式操作替代时明确报告已替代，不返回后继结果。
                    let projection = managed
                        .store
                        .binding_for_chat(&chat_id, &bot_id, &workspace_id)
                        .await?;
                    if projection.status == "bound"
                        && projection.creation_id == existing_creation
                        && projection.thread_id.as_deref() == Some(existing_thread.as_str())
                    {
                        let binding = product_binding(&bot_id, &workspace_id, projection);
                        return Ok(binding_reply(
                            operation_id,
                            &owner_epoch,
                            binding,
                            CommandDisposition::NoChange,
                        ));
                    }
                    if projection.creation_id == existing_creation {
                        // 同一创建身份却不是该完成结果：持久身份自相矛盾，不默认化。
                        return Err(super::storage::binding_needs_recovery());
                    }
                    if projection.creation_id.is_empty() {
                        // 当前行没有可比较的创建身份：无法证明是后继操作，也不猜成已替代。
                        return Err(super::storage::binding_needs_recovery());
                    }
                    return Err(super::storage::binding_superseded());
                }
                // 已持久受理但未完成的同一操作：沿用原创建身份继续，不重复切换绑定，
                // 也不因名称、可信范围或启停等非身份配置变化重新创建。
                // 未完成的绑定还必须仍归属本创建：被后继显式操作切换过时不再写回。
                budget.reserve_more(super::occupancy::counted_text_bytes([(
                    existing_creation.as_str(),
                    1,
                )])?)?;
                let projection = managed
                    .store
                    .binding_for_chat(&chat_id, &bot_id, &workspace_id)
                    .await?;
                if projection.creation_id != existing_creation {
                    return Err(super::storage::binding_needs_recovery());
                }
                // 接续身份与提交给创建接口的克隆、Studio 交回身份及 SQL 参数同时跨 await
                // 存活（峰值见 `CREATE_CALL_CREATION_COPIES`）：首写前补足余下份数。
                budget.reserve_more(super::occupancy::counted_extra_bytes(
                    0,
                    [(existing_creation.len(), CREATE_CALL_CREATION_COPIES - 1)],
                )?)?;
                existing_creation
            } else {
                // 首次受理：预期配置 revision 必须等于当前权威值。
                if current_revision != expected_config_revision {
                    return Err(FeishuError::new(
                        FeishuErrorKind::Conflict,
                        "stale bot config revision",
                        true,
                        None,
                    ));
                }
                let projection = managed
                    .store
                    .binding_for_chat(&chat_id, &bot_id, &workspace_id)
                    .await?;
                let provable_partial = projection.status == "creating"
                    && !projection
                        .thread_id
                        .as_ref()
                        .is_some_and(|id| !id.is_empty())
                    && projection.creation_id == creation_id
                    && projection.workspace_id == workspace_id
                    && Some(projection.revision) == expected_binding_revision.checked_add(1);
                // 进入 job 时已按 1 份预冻结本次派生身份；首写前补足创建调用链的
                // job 持有峰值（见 `CREATE_CALL_CREATION_COPIES`），使单项放不下只会在
                // 任何持久写之前被判定。
                budget.reserve_more(super::occupancy::counted_text_bytes([(
                    creation_id.as_str(),
                    CREATE_CALL_CREATION_COPIES - 1,
                )])?)?;
                // 绑定投影行在随后的 adopt/begin 期间仍存活：按其读取到的实际字段计权。
                budget.reserve_more(projection_freeze_bytes(&projection, 1)?)?;
                let operation = super::storage::BindingOperation {
                    operation_id: operation_id.clone(),
                    bot_id: bot_id.clone(),
                    chat_id: chat_id.clone(),
                    content_hash: content_hash.clone(),
                    expected_revision: expected_binding_revision,
                    creation_id: creation_id.clone(),
                    thread_id: None,
                };
                // 操作记录字段与标题已在 FrozenBinding 的冻结预算中覆盖，
                // 因此这里不会在写入之后才发现单项放不下。
                if provable_partial {
                    // 可证明属于本请求的部分现场：只补齐缺失的操作记录，
                    // 不再次切换绑定水位，也不覆盖其他创建。
                    managed
                        .store
                        .adopt_binding_operation(
                            &chat_id,
                            expected_binding_revision,
                            &workspace_id,
                            &operation,
                        )
                        .await?;
                    self.request_publish();
                } else {
                    if projection.status == "creating"
                        && !projection
                            .thread_id
                            .as_ref()
                            .is_some_and(|id| !id.is_empty())
                    {
                        // 无法证明归属的创建中记录：保留现场并要求本机恢复，
                        // 不覆盖其他创建，也不把无接续证明的记录报告为正常进行中。
                        return Err(super::storage::binding_needs_recovery());
                    }
                    // 首次受理：绑定水位切换与操作记录在同一次提交中生效。
                    managed
                        .store
                        .begin_binding_operation(
                            &chat_id,
                            expected_binding_revision,
                            &workspace_id,
                            &operation,
                        )
                        .await?;
                    // 首次真实占用已提交：在任何后继保存 await 之前主动重建。
                    self.request_publish();
                }
                creation_id
            }
        };
        // 创建身份与预生成标题都已在首写前计入预算：这里不再追加、也不再临时派生。
        let created = runtime
            .create_thread_with_id(frozen_creation.clone(), &workspace_id, &title)
            .await
            .map_err(|error| {
                FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    format!("failed to create bot Thread: {error}"),
                    true,
                    None,
                )
            })?;
        {
            let _admission = managed.admission.lock().await;
            self.reject_closed_admission(&managed)?;
            // 只核对身份字段：名称、可信范围或启停等非身份配置变化不应把已创建的
            // 身份变成不可恢复的半状态。短锁内比较，不克隆配置。
            let identity_ok = {
                let current = managed.config.lock().await;
                current.feishu().app_id == app_id && current.workspace_id == workspace_id
            };
            if !identity_ok {
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "bot identity changed before conversation Thread bind",
                    true,
                    None,
                ));
            }
            let stored = managed.store.load_binding_operation(&operation_id).await?;
            if stored
                .filter(|item| {
                    item.creation_id == frozen_creation
                        && item.bot_id == bot_id
                        && item.chat_id == chat_id
                        && item.content_hash == content_hash
                        && item.expected_revision == expected_binding_revision
                })
                .is_none()
            {
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "conversation Thread creation is no longer owned by this operation",
                    true,
                    None,
                ));
            }
            managed
                .store
                .bind_thread(&chat_id, &created.id, &frozen_creation, &workspace_id)
                .await?;
            managed
                .store
                .save_binding_operation(&super::storage::BindingOperation {
                    operation_id: operation_id.clone(),
                    bot_id: bot_id.clone(),
                    chat_id: chat_id.clone(),
                    content_hash,
                    expected_revision: expected_binding_revision,
                    creation_id: frozen_creation,
                    thread_id: Some(created.id.clone()),
                })
                .await?;
        }
        let binding = self
            .conversation_binding(&managed, &bot_id, &workspace_id, &chat_id)
            .await?;
        Ok(binding_reply(
            operation_id,
            &owner_epoch,
            binding,
            CommandDisposition::Applied,
        ))
    }
}
/// 已持久绑定操作与本次请求的严格身份一致：同一 operationId 只能对应同一机器人、
/// 会话、冻结 revision 与内容指纹，否则是不同输入复用同一操作。
fn binding_operation_matches(
    existing: &super::storage::BindingOperation,
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
    content_hash: &str,
    expected_revision: u64,
) -> bool {
    existing.operation_id == operation_id
        && existing.bot_id == bot_id
        && existing.chat_id == chat_id
        && existing.content_hash == content_hash
        && existing.expected_revision == expected_revision
}

fn product_binding(
    bot_id: &str,
    fallback_project: &str,
    projection: super::storage::BindingProjection,
) -> BotConversationThreadBinding {
    let super::storage::BindingProjection {
        chat_id,
        workspace_id: stored_project,
        thread_id,
        revision,
        status,
        diagnostic,
        ..
    } = projection;
    let state = match status.as_str() {
        "bound" if thread_id.is_some() => BotConversationThreadState::Bound,
        "creating" => BotConversationThreadState::Creating,
        _ => BotConversationThreadState::NeedsAttention,
    };
    // 只有真正“没有持久行”的 Absent/rev0 才用当前请求项目兜底；
    // 持久 needs_attention 缺项目是既有事实，不能借当前请求补归属。
    let workspace_id = if stored_project.is_empty() && status == "absent" && revision == 0 {
        fallback_project.to_string()
    } else {
        stored_project
    };
    BotConversationThreadBinding {
        bot_id: bot_id.to_string(),
        chat_id,
        workspace_id,
        thread_id,
        revision,
        state,
        diagnostic: diagnostic.map(|message| BotDiagnostic {
            code: "binding".to_string(),
            message,
            retryable: false,
            platform_code: None,
            guidance: Some("recreateLocalConversation".to_string()),
        }),
    }
}

fn binding_reply(
    operation_id: String,
    owner_epoch: &str,
    binding: BotConversationThreadBinding,
    disposition: CommandDisposition,
) -> BotConversationThreadReply {
    BotConversationThreadReply {
        receipt: StudioCommandReceipt {
            operation_id,
            disposition,
            targets: vec![ResourceStamp {
                resource_key: format!("bot:{}:chat:{}", binding.bot_id, binding.chat_id),
                owner_epoch: owner_epoch.to_string(),
                revision: binding.revision,
            }],
            effect: CommandEffectPoint::Immediate,
            effective: true,
            durable: true,
            requires_identity_observation: false,
        },
        binding,
    }
}

impl BotRuntime {
    /// 沿冻结绑定解析目标 Thread；归档、缺失与跨项目保持 NeedsAttention 语义。
    pub(super) async fn resolve_bound_thread(
        &self,
        managed: &Arc<crate::bots::owner::ManagedBot>,
        runtime: &StudioRuntime,
        inbound: &FrozenInbound,
        binding_revision: u64,
    ) -> Result<String, InboundWorkOutcome> {
        let FrozenInbound {
            bot_id,
            chat_id,
            workspace_id,
            creation_id,
            ..
        } = inbound;
        let config = managed.config.lock().await.clone();
        let claim = managed
            .store
            .claim_thread_binding(chat_id, creation_id, workspace_id)
            .await
            .map_err(|error| binding_failure("thread binding claim failed", error))?;
        let thread_id = match claim {
            crate::bots::storage::ThreadBindingClaim::Bound { thread_id, .. } => thread_id,
            crate::bots::storage::ThreadBindingClaim::Creating { creation_id, .. } => {
                let created = runtime
                    .create_thread_with_id(
                        creation_id.clone(),
                        workspace_id,
                        &format!("{} / {chat_id}", config.name),
                    )
                    .await
                    .map_err(|error| {
                        recoverable(format!("failed to create bot Thread: {error:#}"))
                    })?;
                managed
                    .store
                    .bind_thread(chat_id, &created.id, &creation_id, workspace_id)
                    .await
                    .map_err(|error| binding_failure("thread binding persist failed", error))?
            }
            crate::bots::storage::ThreadBindingClaim::NeedsAttention { diagnostic } => {
                return Err(InboundWorkOutcome::NeedsAttention { diagnostic });
            }
        };
        let projection = managed
            .store
            .binding_for_chat(chat_id, bot_id, workspace_id)
            .await
            .map_err(|error| binding_failure("thread binding read failed", error))?;
        if binding_revision != 0
            && projection.revision != 0
            && projection.revision != binding_revision
        {
            return Err(InboundWorkOutcome::NeedsAttention {
                diagnostic: "inbound was admitted against a previous conversation binding"
                    .to_string(),
            });
        }
        match runtime.find_owned_thread(&thread_id) {
            Ok(Some(existing)) if existing.workspace_id != config.workspace_id => {
                managed
                    .store
                    .mark_binding_attention(chat_id, "bound Thread belongs to another project")
                    .await
                    .map_err(|error| binding_failure("binding attention failed", error))?;
                Err(InboundWorkOutcome::NeedsAttention {
                    diagnostic: "bound Thread belongs to another project".to_string(),
                })
            }
            Ok(Some(existing))
                if existing.visibility != crate::studio::ThreadVisibility::Active =>
            {
                managed
                    .store
                    .mark_binding_attention(chat_id, "bound Thread is archived")
                    .await
                    .map_err(|error| binding_failure("binding attention failed", error))?;
                Err(InboundWorkOutcome::NeedsAttention {
                    diagnostic: "archived Thread cannot accept bot traffic".to_string(),
                })
            }
            Ok(None) => {
                managed
                    .store
                    .mark_binding_attention(chat_id, "bound Thread is missing")
                    .await
                    .map_err(|error| binding_failure("binding attention failed", error))?;
                Err(InboundWorkOutcome::NeedsAttention {
                    diagnostic: "bound Thread is missing".to_string(),
                })
            }
            Err(error) => Err(recoverable(format!(
                "failed to read bound Thread: {error:#}"
            ))),
            Ok(Some(_)) => Ok(thread_id),
        }
    }
}

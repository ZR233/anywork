use super::inbound::{ChatKind, InboundDecision};
use super::occupancy::{OccupancyBudget, generated_id_bytes, projection_freeze_bytes};
use super::operation::DiagnosticSlot;
use super::owner::{BotRuntime, ManagedBot};
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::reply::ReplyIdentity;
use super::storage::{FrozenInbound, InboundAdmit, InboundClaim};
use crate::studio::new_id;
use std::sync::Arc;
use std::sync::atomic::Ordering;

/// 入站受理的冻结文本上界：按占用任务内各持久 await 阶段同时存活的 owned 副本计。
///
/// | 阶段（首写位置） | 副本峰值 |
/// | --- | --- |
/// | `claim_thread_binding` 的 INSERT 参数（首写） | chat/creation/project 各 2 份 |
/// | `admit_inbound` 的 identities/work 两条 INSERT 参数 | 身份/正文/会话/应用/项目/创建各 2 份；bot_id 3 份（入口 String+冻结字段+参数） |
/// | `observe_direct` 的单聊目录参数 | chat/open 各 2 份 |
/// | `claim_inbound_work` 的 SELECT/UPDATE 参数 | bot/chat/message 各 2 份 |
///
/// 派生身份在 admit 与 claim 各构造一次（各自带一份 SQL 参数），两次不同时存活，按 2 份计；
/// worker 身份在写入前按 `new_id` 上界计 2 份。app/project/创建身份不在事件里，由
/// `admit_decided` 在首写前追加。
fn inbound_freeze_bytes(bot_id: &str, decision: &InboundDecision) -> Result<usize, FeishuError> {
    match decision {
        InboundDecision::Ignore => Ok(0),
        InboundDecision::Pairing {
            open_id,
            chat_id,
            display_name,
            ..
        } => {
            // `record_pairing` 与 `observe_direct` 各自构造 SQL 参数，与会话/发送者原值
            // 及配对请求身份同时跨 await 存活；请求身份按 `new_id` 上界计 2 份。
            let base = super::occupancy::counted_text_bytes([
                (bot_id, 1),
                (chat_id.as_str(), 2),
                (open_id.as_str(), 2),
                (display_name.as_deref().unwrap_or(""), 2),
            ])?;
            super::occupancy::counted_extra_bytes(base, [(generated_id_bytes("pair"), 2)])
        }
        InboundDecision::Execute {
            message_id,
            chat_id,
            open_id,
            text,
            attachments,
            content_hash,
            chat_kind,
            ..
        } => {
            let kind = match chat_kind {
                ChatKind::Direct => "direct",
                ChatKind::Group => "group",
            };
            // bot_id 有三份：受理入口持有的 String、入站冻结字段、SQL 参数。
            let base = super::occupancy::counted_text_bytes([
                (bot_id, 3),
                (message_id.as_str(), 2),
                (chat_id.as_str(), 2),
                (open_id.as_str(), 2),
                (text.as_str(), 2),
                (content_hash.as_str(), 2),
                (kind, 2),
            ])?;
            super::occupancy::counted_extra_bytes(
                base,
                [
                    (
                        super::storage::inbound_identity_bytes(bot_id, chat_id, message_id)?,
                        2,
                    ),
                    (generated_id_bytes("botwork"), 2),
                    (attachments.iter().map(|item| item.frozen_bytes()).sum(), 4),
                ],
            )
        }
    }
}

/// 既有工作行返回的真实材料计权：`admit_inbound` 提交后解出的 payload 会带着进入
/// `observe_direct` 与 `enqueue_inbound`/`claim_inbound_work` 的等待，随后交回复 owner。
/// 每字段按 2 份计（payload 本体 + 各自 SQL 参数或交接克隆）；`watch_input` 无固定上限，
/// 按真实长度计，合法空串为 0 字节。
fn resume_payload_bytes(payload: &FrozenInbound) -> Result<usize, FeishuError> {
    let base = super::occupancy::counted_text_bytes([
        (payload.bot_id.as_str(), 2),
        (payload.message_id.as_str(), 2),
        (payload.chat_id.as_str(), 2),
        (payload.open_id.as_str(), 2),
        (payload.text.as_str(), 2),
        (payload.content_hash.as_str(), 2),
        (payload.chat_kind.as_str(), 2),
        (payload.app_id.as_str(), 2),
        (payload.workspace_id.as_str(), 2),
        (payload.creation_id.as_str(), 2),
        (payload.watch_input.as_str(), 2),
    ])?;
    super::occupancy::counted_extra_bytes(
        base,
        [
            (
                super::storage::inbound_identity_bytes(
                    &payload.bot_id,
                    &payload.chat_id,
                    &payload.message_id,
                )?,
                2,
            ),
            (generated_id_bytes("botwork"), 2),
            (
                payload
                    .attachments
                    .iter()
                    .map(|attachment| attachment.frozen_bytes())
                    .sum(),
                2,
            ),
        ],
    )
}

impl BotRuntime {
    pub(crate) async fn admit_decision(
        &self,
        bot_id: &str,
        connection_generation: u64,
        decision: InboundDecision,
    ) -> Result<(), FeishuError> {
        let managed = self.managed(bot_id).await?;
        if matches!(decision, InboundDecision::Ignore) {
            // 没有持久写入：不占用受管任务，也没有需要重建的能力变化。
            return Ok(());
        }
        let bot_id = bot_id.to_string();
        let text_bytes = inbound_freeze_bytes(&bot_id, &decision)?;
        let worker = self.clone();
        // 真实受理区归受管占用任务：调用方（连接任务）取消只是不再等待回执，
        // 已提交的受理、配对、通知与入站工作登记仍由 owner 完成。
        self.submit_occupancy(text_bytes, move |budget| async move {
            worker
                .admit_decided(managed, &bot_id, connection_generation, decision, budget)
                .await
        })
        .await
    }

    /// 真实受理区（配对与执行）；只在受管占用任务中运行。
    async fn admit_decided(
        &self,
        managed: Arc<ManagedBot>,
        bot_id: &str,
        connection_generation: u64,
        decision: InboundDecision,
        mut budget: OccupancyBudget,
    ) -> Result<(), FeishuError> {
        match decision {
            InboundDecision::Ignore => Ok(()),
            InboundDecision::Pairing {
                open_id,
                chat_id,
                display_name,
                chat_kind,
            } => {
                {
                    let _admission = managed.admission.lock().await;
                    self.reject_closed_admission(&managed)?;
                    if managed.generation.load(Ordering::Acquire) != connection_generation {
                        return Err(FeishuError::new(
                            FeishuErrorKind::Unavailable,
                            "stale inbound connection generation",
                            true,
                            None,
                        ));
                    }
                    // 配对请求身份及其 SQL 参数已在冻结预算中按 `new_id` 上界覆盖。
                    let request_id = new_id("pair");
                    managed
                        .store
                        .record_pairing(&request_id, &open_id, display_name.as_deref())
                        .await?;
                    if chat_kind == ChatKind::Direct {
                        managed
                            .store
                            .observe_direct(&chat_id, Some(&open_id), display_name.as_deref())
                            .await?;
                    }
                }
                self.request_publish();
                Ok(())
            }
            InboundDecision::Execute {
                message_id,
                chat_id,
                open_id,
                text,
                attachments,
                content_hash,
                chat_kind,
            } => {
                let admitted = {
                    let _admission = managed.admission.lock().await;
                    self.reject_closed_admission(&managed)?;
                    if managed.generation.load(Ordering::Acquire) != connection_generation {
                        return Err(FeishuError::new(
                            FeishuErrorKind::Unavailable,
                            "stale inbound connection generation",
                            true,
                            None,
                        ));
                    }
                    // 只取本路径真正需要的配置标量，并在首次持久写之前计入预算；
                    // 不克隆整份配置，也不跨 DB await 持有 config guard。
                    let (app_id, workspace_id) = {
                        let current = managed.config.lock().await;
                        (
                            current.feishu().app_id.clone(),
                            current.workspace_id.clone(),
                        )
                    };
                    // app/project 会与工作行 INSERT 的 SQL 参数同时存活：按 2 份计。
                    budget.reserve_more(super::occupancy::counted_text_bytes([
                        (app_id.as_str(), 2),
                        (workspace_id.as_str(), 2),
                    ])?)?;
                    let creation_id = format!("botthread:{bot_id}:{chat_id}");
                    // 派生创建身份同时存在于 claim 的 INSERT 参数与工作行参数：按 2 份计。
                    budget.reserve_more(super::occupancy::counted_text_bytes([(
                        creation_id.as_str(),
                        2,
                    )])?)?;
                    // claim 可能写入 NoRow 新行：该行投影的会话/项目/创建身份/固定状态
                    // 在写入后必然被读取并存活到 admit，因此在其可能写入之前按完整可知
                    // 上界预留，而不是写完之后才判单项是否放得下。
                    budget.reserve_more(super::occupancy::counted_text_bytes([
                        (chat_id.as_str(), 1),
                        (workspace_id.as_str(), 1),
                        (creation_id.as_str(), 2),
                        ("creating", 1),
                    ])?)?;
                    // This check and the later frozen-target check run under managed.admission,
                    // the same lock permanent deletion takes before its final ledger clear.
                    self.ensure_reply_admission(&workspace_id, &creation_id)
                        .await?;
                    let claim = managed
                        .store
                        .claim_thread_binding(&chat_id, &creation_id, &workspace_id)
                        .await?;
                    // claim 落盘即把该 chat 的会话绑定写入 thread_bindings，
                    // 身份占用由空变为非空，正是 canChangeProject 的真实来源。
                    // notify_one 既不取锁也不挂起，可在受理临界区内直接把该事实交给
                    // 既有合并发布链；之后的失败、partial 写入或 ACK 前取消
                    // 都不会让 canonical 能力投影停留在旧值。
                    self.request_publish();
                    if let super::storage::ThreadBindingClaim::NeedsAttention { diagnostic } =
                        &claim
                    {
                        return Err(FeishuError::new(
                            FeishuErrorKind::Unavailable,
                            diagnostic.clone(),
                            false,
                            None,
                        ));
                    }
                    // claim 自带的身份副本在读取持久投影前释放：后续只按投影事实计权，
                    // 不把两份读出的身份同时留到 admit。
                    drop(claim);
                    // 冻结真实绑定身份与版本：以持久投影为准，不用本次临时派生
                    // 或常数水位替代既有本地上下文。
                    let projection = managed
                        .store
                        .binding_for_chat(&chat_id, bot_id, &workspace_id)
                        .await?;
                    self.ensure_reply_admission(&workspace_id, &projection.creation_id)
                        .await?;
                    if let Some(target) = &projection.thread_id {
                        self.ensure_reply_admission(&workspace_id, target).await?;
                    }
                    if projection.creation_id.is_empty() {
                        return Err(super::storage::binding_needs_recovery());
                    }
                    if projection.workspace_id != workspace_id {
                        // 绑定归属的项目才是权威：不允许把受理写进另一项目。
                        return Err(FeishuError::new(
                            FeishuErrorKind::Conflict,
                            "bot project changed after conversation Thread binding",
                            false,
                            None,
                        ));
                    }
                    // 新行形状的投影已在上方按可知上界预留；既有行（claim 未写入）可能带
                    // 更大的历史创建身份、Thread 身份、状态与诊断，此时按其真实字段追加。
                    let new_row_projection = projection.creation_id == creation_id
                        && projection.workspace_id == workspace_id
                        && projection.chat_id == chat_id
                        && projection.thread_id.is_none()
                        && projection.status == "creating"
                        && projection.diagnostic.is_none();
                    if !new_row_projection {
                        budget.reserve_more(projection_freeze_bytes(&projection, 2)?)?;
                    }
                    let (frozen_creation, frozen_revision) =
                        (projection.creation_id, projection.revision);
                    let inbound = FrozenInbound {
                        bot_id: bot_id.to_string(),
                        message_id,
                        chat_id,
                        content_hash,
                        text,
                        attachments,
                        open_id,
                        chat_kind: match chat_kind {
                            ChatKind::Direct => "direct".to_string(),
                            ChatKind::Group => "group".to_string(),
                        },
                        app_id,
                        workspace_id,
                        creation_id: frozen_creation,
                        binding_revision: frozen_revision,
                        watch_input: String::new(),
                    };
                    // 首次受理沿用本次冻结输入本身，重复命中的续跑身份只接受持久值：
                    // 两路都不再为同一份材料额外复制一遍正文与身份。
                    // 按值移入受理：首次受理把同一份冻结输入交回，不再复制正文与身份；
                    // 重复命中的续跑身份只接受持久值。
                    let admitted = managed.store.admit_inbound(inbound).await?;
                    match &admitted {
                        InboundAdmit::DuplicateResume(payload) => {
                            // 既有工作行的真实材料（含无固定上限的 watch_input）会带着
                            // 进入 observe/enqueue 的下一次等待：按实际字段先计权。
                            budget.reserve_more(resume_payload_bytes(payload)?)?;
                            if payload.chat_kind == "direct" {
                                managed
                                    .store
                                    .observe_direct(&payload.chat_id, Some(&payload.open_id), None)
                                    .await?;
                            }
                        }
                        InboundAdmit::Fresh(payload) if payload.chat_kind == "direct" => {
                            managed
                                .store
                                .observe_direct(&payload.chat_id, Some(&payload.open_id), None)
                                .await?;
                        }
                        _ => {}
                    }
                    admitted
                };
                match admitted {
                    InboundAdmit::DuplicateCompleted => Ok(()),
                    InboundAdmit::Fresh(payload) | InboundAdmit::DuplicateResume(payload) => {
                        self.enqueue_inbound(payload).await
                    }
                }
            }
        }
    }

    pub(super) async fn enqueue_inbound(&self, inbound: FrozenInbound) -> Result<(), FeishuError> {
        if self.inner.sealed.load(Ordering::SeqCst) != 0 {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot runtime is sealed",
                true,
                None,
            ));
        }
        let worker_id = new_id("botwork");
        let managed = self.managed(&inbound.bot_id).await?;
        // Reap before acquiring budget: a finished task still owns its permit
        // until the registration owner observes its join and ledger ACK.
        let mut replies = self.inner.reply_work.tasks.lock().await;
        replies.reap();
        replies.retry_finishes(self, None).await?;
        if self.inner.sealed.load(Ordering::SeqCst) != 0 {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot runtime is sealed",
                true,
                None,
            ));
        }
        let binding = managed
            .store
            .binding_for_chat(&inbound.chat_id, &inbound.bot_id, &inbound.workspace_id)
            .await?;
        // Never route a failed/attention read as an absent binding. A bound
        // Thread is authoritative; only a proven creation may use creation_id.
        let registered_thread_id = match binding.status.as_str() {
            "bound" => binding
                .thread_id
                .ok_or_else(super::storage::binding_needs_recovery)?,
            "creating"
                if binding.thread_id.is_none()
                    && binding.creation_id == inbound.creation_id
                    && binding.revision == inbound.binding_revision
                    && !inbound.creation_id.is_empty() =>
            {
                inbound.creation_id.clone()
            }
            "absent"
                if binding.thread_id.is_none()
                    && binding.revision == inbound.binding_revision
                    && inbound.binding_revision == 0
                    && !inbound.creation_id.is_empty() =>
            {
                inbound.creation_id.clone()
            }
            _ => return Err(super::storage::binding_needs_recovery()),
        };
        // Admission and registration share archive's mutex. Reject before
        // claiming, so a rejected dispatch creates no new finisher obligation.
        self.ensure_reply_admission(&inbound.workspace_id, &registered_thread_id)
            .await?;
        let Ok(permit) = self.inner.reply_work.slots.clone().try_acquire_owned() else {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot reply budget is full",
                true,
                None,
            ));
        };
        match managed
            .store
            .claim_inbound_work(
                &inbound.bot_id,
                &inbound.chat_id,
                &inbound.message_id,
                &worker_id,
            )
            .await?
        {
            InboundClaim::Completed => {
                drop(permit);
                return Ok(());
            }
            InboundClaim::Busy => {
                drop(permit);
                // 重复推送/重连命中的是同一持久身份下进行中的工作：
                // 受理已完成，重复消息无需再受理，也不能重复启动模型。
                return Ok(());
            }
            InboundClaim::Missing => {
                drop(permit);
                return Err(FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    "inbound work is missing after admit",
                    true,
                    None,
                ));
            }
            InboundClaim::NeedsAttention => {
                drop(permit);
                return Ok(());
            }
            // 退避未到期：留给到期后的恢复扫描，不占 reply 槽位。
            InboundClaim::NotDue => {
                drop(permit);
                return Ok(());
            }
            InboundClaim::Claimed => {}
        }
        let runtime = self.clone();
        let cancel = self.inner.reply_work.cancel.child_token();
        let identity = ReplyIdentity::new(&inbound, &worker_id);
        let admission = if self.inner.sealed.load(Ordering::SeqCst) != 0 {
            Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot runtime is sealed",
                true,
                None,
            ))
        } else {
            self.ensure_reply_admission(&inbound.workspace_id, &registered_thread_id)
                .await
        };
        if let Err(error) = admission {
            replies
                .finish_unstarted(self, registered_thread_id, identity, cancel, permit)
                .await?;
            return Err(error);
        }
        let dispatch_thread_id = registered_thread_id.clone();
        replies.spawn(
            registered_thread_id,
            identity.clone(),
            cancel.clone(),
            permit,
            async move {
                let outcome = runtime
                    .dispatch_prompt(inbound, &worker_id, &dispatch_thread_id, cancel)
                    .await;
                runtime.finish_reply(identity, outcome).await
            },
        );
        Ok(())
    }

    pub(crate) async fn restore_unfinished_inbound(&self, bot_id: &str) -> Result<(), FeishuError> {
        let managed = self.managed(bot_id).await?;
        // 只恢复到期工作：pending、退避到期的 failed 与租约过期的 claimed。
        // 退避未到期的工作不被固定频率重派，正常 Pending/待本地交互不耗失败预算。
        let due = managed.store.list_due_inbound(bot_id).await?;
        for inbound in due {
            if let Err(error) = self.enqueue_inbound(inbound).await {
                tracing::warn!(bot_id, %error, "failed to restore unfinished inbound work");
                managed
                    .diagnostic
                    .lock()
                    .await
                    .set(DiagnosticSlot::Directory, Some(error.diagnostic()));
            }
        }
        Ok(())
    }

    pub(crate) async fn ensure_inbound_recovery(&self) -> Result<(), FeishuError> {
        if self.runtime_released() {
            return Ok(());
        }
        let mut slot = self.inner.reply_work.recovery.lock().await;
        if self.runtime_released() {
            return Ok(());
        }
        if slot.as_ref().is_some_and(|handle| !handle.is_finished()) {
            return Ok(());
        }
        join_inbound_recovery(&mut slot).await?;
        if self.inner.sealed.load(Ordering::SeqCst) != 0 {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot runtime is sealed",
                true,
                None,
            ));
        }
        let runtime = self.clone();
        let cancel = self.inner.reply_work.cancel.clone();
        let handle = tokio::spawn(async move {
            loop {
                tokio::select! {
                    _ = cancel.cancelled() => return,
                    _ = tokio::time::sleep(std::time::Duration::from_secs(5)) => {}
                }
                if runtime.inner.sealed.load(Ordering::SeqCst) != 0 {
                    return;
                }
                let bots = runtime
                    .inner
                    .bots
                    .lock()
                    .await
                    .iter()
                    .filter_map(|(id, record)| record.published.as_ref().map(|_| id.clone()))
                    .collect::<Vec<_>>();
                for bot_id in bots {
                    if let Err(error) = runtime.restore_unfinished_inbound(&bot_id).await {
                        tracing::warn!(bot_id, %error, "inbound recovery sweep failed");
                    }
                }
            }
        });
        *slot = Some(handle);
        if self.inner.sealed.load(Ordering::SeqCst) != 0 {
            self.inner.reply_work.cancel.cancel();
            join_inbound_recovery(&mut slot).await?;
        }
        Ok(())
    }
}
pub(super) async fn join_inbound_recovery(
    slot: &mut Option<tokio::task::JoinHandle<()>>,
) -> Result<(), FeishuError> {
    super::join_owned_task(slot).await.map_err(|_| {
        FeishuError::new(
            FeishuErrorKind::Unavailable,
            "bot inbound recovery join failed",
            true,
            None,
        )
    })
}

#[cfg(test)]
mod tests;

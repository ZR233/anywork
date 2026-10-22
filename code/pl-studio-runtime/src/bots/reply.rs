//! 入站受理后的正式自动回复：状态流只唤醒，结局从持久 canonical 事实重建。
//!
//! 首次进入、Lagged、观察重开与进程重启共用同一条恢复链：durable 输入路由/消费
//! 身份 → 原目标 Turn 的 typed 状态 → 交互终局事实。没有 active Turn 不等于原输入
//! 未执行；Absent 与 NotReady 分别表达，读/IO/decode 错误按分类退避而不是折叠成
//! 结局。等待循环与认领续约协调：runtime 停止是 Interrupted（保留未决、释放认领为
//! pending），失租是 LostClaim（停止旧观察与新副作用）；两者都不冒充本地明确的
//! 交互结束。

use super::InboundWorkOutcome;
use super::owner::BotRuntime;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::storage::{ClaimLease, FrozenInbound, MarkOutcome};
use super::{BotInputRead, BotInteractionKind, BotInteractionRead, BotTurnRead};
use crate::studio::{StudioRuntime, StudioThreadSubscription, TimelineTailStream};
use pl_core::thread::input::{InputDelivery, InputState};
use pl_protocol::{
    InteractionStatus, ThreadContentField, ThreadItemKind, ThreadItemState,
    ThreadSubscriptionRequest, ThreadTextChannel, TimelineDetailQuery, TimelineItem,
    TimelineLifecycle, TimelinePageQuery, TurnCancellationCause, TurnCompletion, TurnState,
};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::Arc;
use std::sync::atomic::Ordering;
use std::time::Duration;
use tokio_util::sync::CancellationToken;

/// 认领续约节奏：60 秒租约内保留多次续约机会；等待本身不耗失败预算。
const CLAIM_RENEW_INTERVAL: Duration = Duration::from_secs(15);
const MAX_TURN_CONTENT_ITEMS: usize = 16_384;
const MAX_TURN_BODY_BYTES: usize = 800_000;

/// 一次入站工作的恢复执行进度；`watch_input` 是当前 canonical 输入身份。
struct ReplyRun {
    bot_id: String,
    chat_id: String,
    message_id: String,
    text: String,
    worker_id: String,
    thread_id: String,
    original_input: String,
    watch_input: String,
    /// 本执行内已受理的提示；真正的去重由发送账本的稳定操作身份保证。
    hinted: BTreeSet<String>,
}

impl ReplyRun {
    fn watching_original(&self) -> bool {
        self.watch_input == self.original_input
    }
}

enum Step {
    /// 已得出终局。
    Done(InboundWorkOutcome),
    /// 事实尚未就绪：等待流唤醒或下一轮续约重建。
    Wait,
    /// 本轮副作用已提交（首次 submit / continuation 切换），立即重建进度。
    Continue,
}

enum ClaimGuard {
    Held,
    Lost,
}

/// 认领租约的并发续约循环：与主执行同任务并发，不是失管后台任务。
///
/// 只在「续约被有效 lease 条件拒绝或无法确认」时完成并报告失租；cancel 之后保持
/// 挂起，把 runtime 停止的收束留给主执行的 Interrupted 路径。与 dispatch 结束后的
/// finish 不会产生顺序竞态：finish 自身带同一有效 lease + 持有者条件，迟到的续约
/// 在收束后命中 0 行条件更新，不会复活已收束的状态。
async fn heartbeat_claims(
    runtime: BotRuntime,
    keys: (String, String, String),
    worker_id: String,
    cancel: CancellationToken,
) {
    let (bot_id, chat_id, message_id) = keys;
    loop {
        tokio::select! {
            _ = cancel.cancelled() => {
                // runtime 停止：挂起自身，主执行的 cancel 分支负责 Interrupted 收束。
                std::future::pending::<()>().await;
            }
            _ = tokio::time::sleep(CLAIM_RENEW_INTERVAL) => {}
        }
        let renewed = match runtime.managed(&bot_id).await {
            Ok(managed) => {
                managed
                    .store
                    .renew_inbound_claim(&bot_id, &chat_id, &message_id, &worker_id)
                    .await
            }
            // 无法确认续约时按失租处理：不再续权、不再发起新动作。
            Err(_) => return,
        };
        match renewed {
            Ok(ClaimLease::Renewed) => {}
            Ok(ClaimLease::LostClaim) | Err(_) => return,
        }
    }
}

impl BotRuntime {
    pub(crate) fn studio_host(&self) -> Option<std::sync::Arc<StudioRuntime>> {
        self.inner
            .host
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .as_ref()
            .and_then(std::sync::Weak::upgrade)
    }

    pub(crate) async fn dispatch_prompt(
        &self,
        inbound: FrozenInbound,
        worker_id: &str,
        cancel: CancellationToken,
    ) -> InboundWorkOutcome {
        // 整个 dispatch（含初始绑定解析、观察打开、屏障、翻页、submit、发送等全部
        // 长 await）与 ≤20s 的认领续约在同一 JoinSet 任务内结构化并发：heartbeat
        // 失租即返回 LostClaim 并丢弃主执行；所有副作用都带稳定身份的幂等受理或
        // 发送账本事实，被丢弃的进行中请求由接管者按原操作核实，不等于未发生、
        // 也不重放。cancel 由主执行自身收束为 Interrupted；heartbeat 在 cancel 后
        // 挂起，不会把 runtime 停止误报成失租。
        let heartbeat_keys = (
            inbound.bot_id.clone(),
            inbound.chat_id.clone(),
            inbound.message_id.clone(),
        );
        let heartbeat_worker = worker_id.to_string();
        tokio::select! {
        outcome = self.run_reply(inbound, worker_id, cancel.clone()) => outcome,
        // heartbeat 只会因失租完成；cancel 后它保持挂起，不误报 runtime 停止。
        _ = heartbeat_claims(self.clone(), heartbeat_keys, heartbeat_worker, cancel.clone()) => {
                InboundWorkOutcome::LostClaim
            }
        }
    }

    async fn run_reply(
        &self,
        inbound: FrozenInbound,
        worker_id: &str,
        cancel: CancellationToken,
    ) -> InboundWorkOutcome {
        let run = ReplyRun {
            bot_id: inbound.bot_id.clone(),
            chat_id: inbound.chat_id.clone(),
            message_id: inbound.message_id.clone(),
            text: inbound.text.clone(),
            worker_id: worker_id.to_string(),
            thread_id: String::new(),
            original_input: bot_input_id(&inbound.bot_id, &inbound.chat_id, &inbound.message_id),
            watch_input: if inbound.watch_input.is_empty() {
                bot_input_id(&inbound.bot_id, &inbound.chat_id, &inbound.message_id)
            } else {
                inbound.watch_input.clone()
            },
            hinted: BTreeSet::new(),
        };
        if self.inner.sealed.load(Ordering::SeqCst) != 0 || cancel.is_cancelled() {
            return InboundWorkOutcome::Interrupted;
        }
        let Some(runtime) = self.studio_host() else {
            return InboundWorkOutcome::Recoverable {
                diagnostic: "studio runtime host is unavailable".to_string(),
            };
        };
        let managed = match self.managed(&run.bot_id).await {
            Ok(managed) => managed,
            Err(error) => return attention(format!("bot runtime lost before reply: {error}")),
        };
        let config = managed.config.lock().await.clone();
        if config.project_id != inbound.project_id {
            return attention("frozen inbound project no longer matches bot config");
        }
        // 冻结路由：入站受理时的 App/project/creation/binding 归属不因新配置改派。
        let thread_id = match self
            .resolve_bound_thread(&managed, &runtime, &inbound, inbound.binding_revision)
            .await
        {
            Ok(thread_id) => thread_id,
            Err(outcome) => return outcome,
        };
        let mut run = run;
        run.thread_id = thread_id;
        let mut watch = match ReplyWatch::open(&runtime, &run.thread_id).await {
            Ok(watch) => watch,
            Err(error) => return classify_send_error(error),
        };
        loop {
            if cancel.is_cancelled() || self.inner.sealed.load(Ordering::SeqCst) != 0 {
                return InboundWorkOutcome::Interrupted;
            }
            match self.renew_claim(&run).await {
                ClaimGuard::Held => {}
                ClaimGuard::Lost => return InboundWorkOutcome::LostClaim,
            }
            match self.advance(&runtime, &mut run, &cancel).await {
                Step::Done(outcome) => return outcome,
                Step::Continue => continue,
                Step::Wait => {
                    if let Err(error) = watch.ensure_alive(&runtime, &run.thread_id).await {
                        return classify_send_error(error);
                    }
                    if let Step::Done(outcome) = watch.wait(&cancel).await {
                        return outcome;
                    }
                }
            }
        }
    }

    async fn renew_claim(&self, run: &ReplyRun) -> ClaimGuard {
        let Ok(managed) = self.managed(&run.bot_id).await else {
            return ClaimGuard::Lost;
        };
        match managed
            .store
            .renew_inbound_claim(&run.bot_id, &run.chat_id, &run.message_id, &run.worker_id)
            .await
        {
            Ok(ClaimLease::Renewed) => ClaimGuard::Held,
            // 失租或续约无法确认：停止旧观察与新动作，不取消其他工作。
            Ok(ClaimLease::LostClaim) | Err(_) => ClaimGuard::Lost,
        }
    }

    /// 一轮 canonical 重建：输入路由 → 目标 Turn → 交互终局。
    async fn advance(
        &self,
        runtime: &StudioRuntime,
        run: &mut ReplyRun,
        cancel: &CancellationToken,
    ) -> Step {
        let input = match runtime
            .bot_input_fact(&run.thread_id, &run.watch_input)
            .await
        {
            Ok(input) => input,
            Err(error) => {
                return Step::Done(recoverable(format!(
                    "canonical input identity read failed: {error:#}"
                )));
            }
        };
        let input = match input {
            BotInputRead::Ready { delivery, state } => (delivery, state),
            BotInputRead::Absent => {
                if run.watching_original() {
                    return self.submit_original(runtime, run).await;
                }
                // continuation 输入尚未持久化：事实未定，保持待定等待。
                return Step::Wait;
            }
        };
        match input {
            (InputDelivery::CurrentTurn { .. }, _) => {
                Step::Done(attention("bot input was routed onto a concurrent turn"))
            }
            (InputDelivery::NextTurn, InputState::Pending) => Step::Wait,
            (InputDelivery::NextTurn, InputState::Discarded) => {
                Step::Done(InboundWorkOutcome::Completed)
            }
            (InputDelivery::NextTurn, InputState::Consumed { turn_id, .. }) => {
                self.advance_turn(runtime, run, &turn_id, cancel).await
            }
        }
    }

    /// 原输入尚未被 Studio 受理：以稳定输入身份幂等提交；重复提交命中原受理事实。
    async fn submit_original(&self, runtime: &StudioRuntime, run: &ReplyRun) -> Step {
        match runtime
            .submit_prompt(crate::studio::StudioSubmitPromptRequest {
                thread_id: run.thread_id.clone(),
                input: pl_protocol::studio::StudioPromptInput {
                    input_id: run.original_input.clone(),
                    text: run.text.clone(),
                    attachment_draft_ids: Vec::new(),
                },
                options: crate::studio::StudioSubmitPromptOptions::default(),
            })
            .await
        {
            // 受理后首个 effect 落库前身份仍可能 Absent；等待唤醒后重建，不连续重提。
            Ok(_) => Step::Wait,
            Err(error) => Step::Done(recoverable(format!("bot prompt submit failed: {error:#}"))),
        }
    }

    async fn advance_turn(
        &self,
        runtime: &StudioRuntime,
        run: &mut ReplyRun,
        turn_id: &str,
        cancel: &CancellationToken,
    ) -> Step {
        let turn = match runtime.bot_turn_fact(&run.thread_id, turn_id).await {
            Ok(turn) => turn,
            Err(error) => {
                return Step::Done(recoverable(format!(
                    "canonical turn fact read failed: {error:#}"
                )));
            }
        };
        let state = match turn {
            BotTurnRead::Ready(state) => state,
            // 消费身份指向的 Turn 尚未持久化；不推断结局，等待重建。
            BotTurnRead::Absent => return Step::Wait,
        };
        match state {
            TurnState::Queued(_) | TurnState::Running(_) => {
                self.hint_pending_interactions(runtime, run, turn_id, cancel)
                    .await
            }
            TurnState::Completed(state) => match state.completion() {
                TurnCompletion::Normal => {
                    self.finish_with_final_text(runtime, run, turn_id, cancel)
                        .await
                }
                TurnCompletion::InteractionRequested => {
                    self.advance_interactions(runtime, run, turn_id, cancel)
                        .await
                }
            },
            TurnState::Cancelled(state)
                if matches!(state.cause(), TurnCancellationCause::Interrupted) =>
            {
                // runtime 停止造成的中断保留未决：释放认领为 pending，重启立即可恢复。
                Step::Done(InboundWorkOutcome::Interrupted)
            }
            // 其余终态是本地明确的结束决定：completed-no-reply，不重复执行原输入。
            TurnState::Cancelled(_) | TurnState::Failed(_) | TurnState::BudgetLimited(_) => {
                Step::Done(InboundWorkOutcome::Completed)
            }
        }
    }

    /// Turn 以交互请求收尾：边界终局只由 UserInput 类交互决定。
    ///
    /// 权限记录与 UserInput 交互共存于同一 Turn 的快照（core 驻留保留 settled
    /// permission record）：已决议权限只说明原 Turn 曾恢复执行，Allowed/Denied 都
    /// 不构成此边界的结局，跳过而不终结整个工作；Pending 权限仍等待并提示。
    /// 无法得出任何 UserInput 终局时保持待定，不把只含已决议权限的集合当错误终结。
    async fn advance_interactions(
        &self,
        runtime: &StudioRuntime,
        run: &mut ReplyRun,
        turn_id: &str,
        cancel: &CancellationToken,
    ) -> Step {
        let locals = match self
            .turn_interaction_locals(runtime, run, turn_id, cancel)
            .await
        {
            Ok(locals) => locals,
            Err(outcome) => return Step::Done(outcome),
        };
        if locals.is_empty() {
            // 终态声明有交互但事实尚未可读：保持待定，不解释为无交互。
            return Step::Wait;
        }
        for local in &locals {
            let fact = match runtime.bot_interaction_fact(&run.thread_id, local).await {
                Ok(fact) => fact,
                Err(error) => {
                    return Step::Done(recoverable(format!(
                        "canonical interaction fact read failed: {error:#}"
                    )));
                }
            };
            match fact {
                BotInteractionRead::Ready(fact) => match fact.kind {
                    BotInteractionKind::UserInput => match fact.status {
                        InteractionStatus::Pending => {
                            match self.send_interaction_hint(run, local).await {
                                Step::Done(outcome) => return Step::Done(outcome),
                                Step::Wait | Step::Continue => {}
                            }
                        }
                        InteractionStatus::Resolved => {
                            return match fact.continuation_input {
                                // 沿 canonical continuation 输入继续原答复链。
                                Some(continuation) => {
                                    self.switch_watch_input(run, continuation).await
                                }
                                // 明确无 continuation 的终态决定：completed-no-reply。
                                None => Step::Done(InboundWorkOutcome::Completed),
                            };
                        }
                        InteractionStatus::Cancelled | InteractionStatus::Expired => {
                            return Step::Done(InboundWorkOutcome::Completed);
                        }
                    },
                    BotInteractionKind::Permission => match fact.status {
                        InteractionStatus::Pending => {
                            match self.send_interaction_hint(run, local).await {
                                Step::Done(outcome) => return Step::Done(outcome),
                                Step::Wait | Step::Continue => {}
                            }
                        }
                        // Allowed/Denied（及已取消）的权限只恢复原 Turn 执行，
                        // 不产生 continuation，也不决定本边界的结局：继续
                        // 检查其余交互，由 UserInput 事实裁决。
                        InteractionStatus::Resolved
                        | InteractionStatus::Cancelled
                        | InteractionStatus::Expired => {}
                    },
                },
                // 终局尚未持久或身份尚未可读：待定，不当取消或无 continuation。
                BotInteractionRead::NotReady | BotInteractionRead::Absent => return Step::Wait,
            }
        }
        // 集合中没有可裁决的 UserInput 终局（全部 pending，或只有已决议权限）：
        // 事实尚未可读，保持待定等待，不当错误终结。
        Step::Wait
    }

    /// 发现目标 Turn 的交互 local 身份：统一内容源快照优先，timeline 工具条目兜底。
    async fn turn_interaction_locals(
        &self,
        runtime: &StudioRuntime,
        run: &ReplyRun,
        turn_id: &str,
        cancel: &CancellationToken,
    ) -> Result<BTreeSet<String>, InboundWorkOutcome> {
        let snapshot = runtime
            .thread_snapshot(&run.thread_id)
            .await
            .map_err(|error| recoverable(format!("canonical thread snapshot failed: {error:#}")))?;
        let mut locals = BTreeSet::new();
        for interaction in &snapshot.interactions {
            if interaction.scope.turn_id != turn_id {
                continue;
            }
            if let Ok((_, local)) =
                crate::thread_assembler::decode_interaction_key(&interaction.interaction_id)
            {
                locals.insert(local.to_string());
            }
        }
        if !locals.is_empty() {
            return Ok(locals);
        }
        // 快照不再保留该 Turn 的交互（例如重启窗口内已收束）：从 timeline 的
        // tool.user_input 投影发现 local 身份，仍只读统一内容源。
        discover_timeline_interactions(runtime, &run.thread_id, turn_id, cancel).await
    }

    /// Turn 执行期与终态等待中的 pending 交互逐个提示；每个交互独立稳定键。
    async fn hint_pending_interactions(
        &self,
        runtime: &StudioRuntime,
        run: &mut ReplyRun,
        turn_id: &str,
        cancel: &CancellationToken,
    ) -> Step {
        let locals = match self
            .turn_interaction_locals(runtime, run, turn_id, cancel)
            .await
        {
            Ok(locals) => locals,
            Err(outcome) => return Step::Done(outcome),
        };
        for local in &locals {
            let pending = match runtime.bot_interaction_fact(&run.thread_id, local).await {
                Ok(BotInteractionRead::Ready(fact)) => fact.status == InteractionStatus::Pending,
                // 尚未可读的事实保持待定；提示不是结局依据。
                Ok(_) | Err(_) => false,
            };
            if pending {
                match self.send_interaction_hint(run, local).await {
                    Step::Done(outcome) => return Step::Done(outcome),
                    Step::Wait | Step::Continue => {}
                }
            }
        }
        Step::Wait
    }

    async fn send_interaction_hint(&self, run: &mut ReplyRun, local: &str) -> Step {
        let key = hint_key(local);
        if run.hinted.contains(&key) {
            return Step::Wait;
        }
        // 每个交互独立稳定提示键：既不占用正式回复键，也不抑制后续新交互提示。
        let operation_id = format!("bothint:{}:{}:{}", run.bot_id, run.message_id, local);
        match self
            .send_message_as(
                operation_id,
                run.bot_id.clone(),
                run.chat_id.clone(),
                interaction_hint().to_string(),
                "auto-reply",
                super::SendAuthority::AutoReply,
            )
            .await
        {
            // 提示是辅助通知：已受理的 Unknown/Partial/Rejected 不自动重放，
            // 也不影响正式回复义务；未受理的 retryable 失败下轮重建时再试。
            Ok(_) => {
                run.hinted.insert(key);
                Step::Wait
            }
            Err(error) if error.retryable() => Step::Wait,
            Err(_) => {
                run.hinted.insert(key);
                Step::Wait
            }
        }
    }

    async fn switch_watch_input(&self, run: &mut ReplyRun, continuation: String) -> Step {
        let managed = match self.managed(&run.bot_id).await {
            Ok(managed) => managed,
            Err(_) => return Step::Done(InboundWorkOutcome::LostClaim),
        };
        match managed
            .store
            .save_inbound_watch_input(
                &run.bot_id,
                &run.chat_id,
                &run.message_id,
                &run.worker_id,
                &continuation,
            )
            .await
        {
            Ok(MarkOutcome::Applied) => {
                run.watch_input = continuation;
                Step::Continue
            }
            // 无法确认进度仍归本持有者：按失租处理。
            Ok(MarkOutcome::LostClaim) | Err(_) => Step::Done(InboundWorkOutcome::LostClaim),
        }
    }

    /// Turn 正常完成：证明完整 Final 正文后经统一发送服务回复原会话。
    async fn finish_with_final_text(
        &self,
        runtime: &StudioRuntime,
        run: &ReplyRun,
        turn_id: &str,
        cancel: &CancellationToken,
    ) -> Step {
        let text = tokio::select! {
            _ = cancel.cancelled() => return Step::Done(InboundWorkOutcome::Interrupted),
            collected = collect_complete_turn_text(runtime, &run.thread_id, turn_id) => {
                match collected {
            Ok(FinalText::CompleteText(text)) => text,
                    Ok(FinalText::CompleteNoText) => {
                        return Step::Done(InboundWorkOutcome::Completed)
        }
                    Err(FinalError::Retryable(diagnostic)) => {
                        return Step::Done(recoverable(diagnostic))
                    }
                    Err(FinalError::Attention(diagnostic)) => {
                        return Step::Done(attention(diagnostic))
                    }
                }
            }
        };
        if text.trim().is_empty() {
            return Step::Done(InboundWorkOutcome::Completed);
        }
        // 正文收集可能跨越续约窗口：正式发送前复核认领仍归本持有者。
        match self.renew_claim(run).await {
            ClaimGuard::Held => {}
            ClaimGuard::Lost => return Step::Done(InboundWorkOutcome::LostClaim),
        }
        // 正式回复绑定原 bot/chat/message 稳定键，与提示键互不影响。
        let operation_id = format!("botreply:{}:{}:{}", run.bot_id, run.chat_id, run.message_id);
        match self
            .send_message_as(
                operation_id,
                run.bot_id.clone(),
                run.chat_id.clone(),
                text,
                "auto-reply",
                super::SendAuthority::AutoReply,
            )
            .await
        {
            Ok(result) => Step::Done(match result.status {
                pl_protocol::studio::BotSendStatus::Succeeded => InboundWorkOutcome::Completed,
                // Unknown/Partial/Rejected 遵循原操作事实，不借恢复再次发送。
                _ => attention("auto-reply send did not fully succeed and will not be retried"),
            }),
            Err(error) if error.retryable() => Step::Done(recoverable(format!(
                "auto-reply send failed before the ledger recorded a result: {error}"
            ))),
            Err(error) => Step::Done(attention(format!("auto-reply send was rejected: {error}"))),
        }
    }

    /// 沿冻结绑定解析目标 Thread；归档、缺失与跨项目保持 NeedsAttention 语义。
    async fn resolve_bound_thread(
        &self,
        managed: &Arc<super::owner::ManagedBot>,
        runtime: &StudioRuntime,
        inbound: &FrozenInbound,
        binding_revision: u64,
    ) -> Result<String, InboundWorkOutcome> {
        let FrozenInbound {
            bot_id,
            chat_id,
            project_id,
            creation_id,
            ..
        } = inbound;
        let config = managed.config.lock().await.clone();
        let claim = managed
            .store
            .claim_thread_binding(chat_id, creation_id, project_id)
            .await
            .map_err(|error| binding_failure("thread binding claim failed", error))?;
        let thread_id = match claim {
            super::storage::ThreadBindingClaim::Bound { thread_id, .. } => thread_id,
            super::storage::ThreadBindingClaim::Creating { creation_id, .. } => {
                let created = runtime
                    .create_thread_with_id(
                        creation_id.clone(),
                        project_id,
                        &format!("{} / {chat_id}", config.name),
                    )
                    .await
                    .map_err(|error| {
                        recoverable(format!("failed to create bot Thread: {error:#}"))
                    })?;
                managed
                    .store
                    .bind_thread(chat_id, &created.id, &creation_id, project_id)
                    .await
                    .map_err(|error| binding_failure("thread binding persist failed", error))?
            }
            super::storage::ThreadBindingClaim::NeedsAttention { diagnostic } => {
                return Err(InboundWorkOutcome::NeedsAttention { diagnostic });
            }
        };
        let projection = managed
            .store
            .binding_for_chat(chat_id, bot_id, project_id)
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
        match runtime.find_owned_thread(&thread_id).await {
            Ok(Some(existing)) if existing.project_id != config.project_id => {
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

/// 观察句柄：订阅与有界尾部窗口都只作为唤醒源；失效后由 `ensure_alive` 重开。
struct ReplyWatch {
    subscription: Option<StudioThreadSubscription>,
    window: Option<TimelineTailStream>,
}

impl ReplyWatch {
    async fn open(runtime: &StudioRuntime, thread_id: &str) -> Result<Self, FeishuError> {
        let subscription = runtime
            .subscribe_thread(ThreadSubscriptionRequest {
                thread_id: thread_id.to_string(),
            })
            .await
            .map_err(|error| watch_error("bot Thread subscribe failed", &format!("{error:#}")))?;
        let window = runtime
            .open_timeline_tail(thread_id)
            .await
            .map_err(|error| watch_error("bot chat window failed", &format!("{error:#}")))?;
        Ok(Self {
            subscription: Some(subscription),
            window: Some(window),
        })
    }

    async fn ensure_alive(
        &mut self,
        runtime: &StudioRuntime,
        thread_id: &str,
    ) -> Result<(), FeishuError> {
        if self.subscription.is_none() {
            let subscription = runtime
                .subscribe_thread(ThreadSubscriptionRequest {
                    thread_id: thread_id.to_string(),
                })
                .await
                .map_err(|error| {
                    watch_error("bot Thread resubscribe failed", &format!("{error:#}"))
                })?;
            self.subscription = Some(subscription);
        }
        if self.window.is_none() {
            let window = runtime
                .open_timeline_tail(thread_id)
                .await
                .map_err(|error| {
                    watch_error("bot chat window reopen failed", &format!("{error:#}"))
                })?;
            self.window = Some(window);
        }
        Ok(())
    }

    /// 等待任一唤醒或续约定时；取消是 Interrupted（保留未决），不是本地交互结束。
    async fn wait(&mut self, cancel: &CancellationToken) -> Step {
        let renew = tokio::time::sleep(CLAIM_RENEW_INTERVAL);
        tokio::pin!(renew);
        tokio::select! {
            _ = cancel.cancelled() => Step::Done(InboundWorkOutcome::Interrupted),
            _ = &mut renew => Step::Wait,
            update = subscription_recv(self.subscription.as_mut()) => {
                match update {
                    // 帧内容只作唤醒；结局一律由下一轮 canonical 重建裁决。
                    Ok(Some(_)) => Step::Wait,
                    Ok(None) | Err(_) => {
                        self.subscription = None;
                        Step::Wait
                    }
                }
            }
            update = window_next(self.window.as_mut()) => {
                match update {
                    Ok(Some(_)) => Step::Wait,
                    Ok(None) | Err(_) => {
                        self.window = None;
                        Step::Wait
                    }
                }
            }
        }
    }
}

async fn subscription_recv(
    subscription: Option<&mut StudioThreadSubscription>,
) -> anyhow::Result<Option<pl_protocol::ThreadSubscriptionUpdate>> {
    match subscription {
        Some(subscription) => subscription.recv().await,
        None => std::future::pending().await,
    }
}

async fn window_next(
    window: Option<&mut TimelineTailStream>,
) -> anyhow::Result<Option<pl_protocol::TimelineTailUpdate>> {
    match window {
        Some(window) => window.next().await,
        None => std::future::pending().await,
    }
}

enum FinalError {
    Retryable(String),
    Attention(String),
}

enum FinalText {
    CompleteNoText,
    CompleteText(String),
}

/// 从统一内容源完整收集目标 Turn 的用户可见终态正文；只统计 Final 且 Terminal。
async fn collect_complete_turn_text(
    runtime: &StudioRuntime,
    thread_id: &str,
    turn_id: &str,
) -> Result<FinalText, FinalError> {
    runtime
        .synchronize_thread_observation(thread_id)
        .await
        .map_err(|error| {
            FinalError::Retryable(format!("thread observation barrier failed: {error:#}"))
        })?;
    let mut collected = BTreeMap::new();
    let mut inspected = 0usize;
    let mut body_bytes = 0usize;
    let mut before = None;
    let mut previous_before = None;
    loop {
        let page = runtime
            .timeline_page(
                thread_id,
                &TimelinePageQuery {
                    before: before.clone(),
                    limit: Some(100),
                },
            )
            .await
            .map_err(|error| {
                FinalError::Retryable(format!("canonical timeline page failed: {error:#}"))
            })?;
        if page.thread_id != thread_id {
            return Err(FinalError::Attention(
                "canonical timeline page belongs to another Thread".to_string(),
            ));
        }
        inspected = inspected.saturating_add(page.items.len());
        if inspected > MAX_TURN_CONTENT_ITEMS {
            return Err(FinalError::Attention(
                "canonical turn coverage exceeded 16384 content items".to_string(),
            ));
        }
        for item in page.items {
            if item.preview.turn_id != turn_id {
                continue;
            }
            if item.lifecycle != TimelineLifecycle::Terminal {
                continue;
            }
            let Some(text) = item.preview.text() else {
                continue;
            };
            if text.channel() != ThreadTextChannel::Final || !text.lifecycle().is_terminal() {
                continue;
            }
            let body = if item.omitted_bytes > 0 {
                read_complete_text(runtime, thread_id, &item, &mut body_bytes).await?
            } else {
                account_body_bytes(text.text(), &mut body_bytes)?;
                text.text().to_string()
            };
            collected.insert(item.preview.ordinal, (item.preview.id.clone(), body));
        }
        if !page.has_older {
            break;
        }
        let Some(next) = page.before.filter(|token| !token.is_empty()) else {
            return Err(FinalError::Attention(
                "canonical timeline reported older content without a before cursor".to_string(),
            ));
        };
        if previous_before.as_ref() == Some(&next) {
            return Err(FinalError::Attention(
                "canonical timeline before cursor did not advance".to_string(),
            ));
        }
        previous_before = before.clone();
        before = Some(next);
    }
    if collected.is_empty() {
        return Ok(FinalText::CompleteNoText);
    }
    let mut parts = Vec::new();
    let mut last_id = None;
    for (_ordinal, (id, body)) in collected {
        if last_id.as_ref() == Some(&id) {
            continue;
        }
        last_id = Some(id);
        if !body.trim().is_empty() {
            parts.push(body);
        }
    }
    let joined = parts.join("\n\n");
    if joined.trim().is_empty() {
        return Ok(FinalText::CompleteNoText);
    }
    Ok(FinalText::CompleteText(joined))
}

async fn read_complete_text(
    runtime: &StudioRuntime,
    thread_id: &str,
    item: &TimelineItem,
    body_bytes: &mut usize,
) -> Result<String, FinalError> {
    let mut continuation = None;
    let mut body = String::new();
    let mut previous = None;
    loop {
        let chunk = runtime
            .read_timeline_detail(
                thread_id,
                &item.preview.id,
                &TimelineDetailQuery {
                    field: ThreadContentField::Text,
                    revision: item.preview.revision,
                    continuation,
                    max_bytes: None,
                },
            )
            .await
            .map_err(|error| {
                FinalError::Retryable(format!("canonical timeline detail failed: {error:#}"))
            })?;
        if chunk.thread_id != thread_id || chunk.item_id != item.preview.id {
            return Err(FinalError::Attention(
                "canonical timeline detail identity conflict".to_string(),
            ));
        }
        if chunk.revision != item.preview.revision {
            return Err(FinalError::Attention(
                "canonical timeline detail revision conflict".to_string(),
            ));
        }
        if chunk.total_bytes > MAX_TURN_BODY_BYTES as u64 {
            return Err(FinalError::Attention(
                "canonical turn text exceeded 800000 UTF-8 bytes".to_string(),
            ));
        }
        account_body_bytes(&chunk.text, body_bytes)?;
        body.push_str(&chunk.text);
        match chunk.continuation {
            Some(token) if previous.as_ref() == Some(&token) => {
                return Err(FinalError::Attention(
                    "canonical timeline detail continuation did not advance".to_string(),
                ));
            }
            Some(token) => {
                previous = Some(token.clone());
                continuation = Some(token);
            }
            None => break,
        }
    }
    Ok(body)
}

fn account_body_bytes(text: &str, body_bytes: &mut usize) -> Result<(), FinalError> {
    *body_bytes = body_bytes.saturating_add(text.len());
    if *body_bytes > MAX_TURN_BODY_BYTES {
        return Err(FinalError::Attention(
            "canonical turn text exceeded 800000 UTF-8 bytes".to_string(),
        ));
    }
    Ok(())
}

/// timeline 兜底：快照不再保留该 Turn 的交互时，从 tool.user_input 投影发现 local 身份。
async fn discover_timeline_interactions(
    runtime: &StudioRuntime,
    thread_id: &str,
    turn_id: &str,
    cancel: &CancellationToken,
) -> Result<BTreeSet<String>, InboundWorkOutcome> {
    let mut locals = BTreeSet::new();
    let mut before = None;
    let mut previous_before = None;
    let mut inspected = 0usize;
    loop {
        let query = TimelinePageQuery {
            before: before.clone(),
            limit: Some(100),
        };
        let page = tokio::select! {
            _ = cancel.cancelled() => {
                return Err(InboundWorkOutcome::Interrupted);
            }
            page = runtime.timeline_page(thread_id, &query) => page.map_err(|error| {
                recoverable(format!("canonical timeline page failed: {error:#}"))
            })?,
        };
        inspected = inspected.saturating_add(page.items.len());
        if inspected > MAX_TURN_CONTENT_ITEMS {
            return Err(attention(
                "canonical interaction discovery exceeded 16384 content items",
            ));
        }
        for item in page.items {
            if item.preview.turn_id != turn_id {
                continue;
            }
            if item.preview.kind() != ThreadItemKind::Tool {
                continue;
            }
            if let ThreadItemState::Tool(tool_item) = item.preview.state()
                && let Some(user_input) = tool_item.user_input()
            {
                locals.insert(user_input.interaction_id().to_string());
            }
        }
        if !page.has_older {
            break;
        }
        let Some(next) = page.before.filter(|token| !token.is_empty()) else {
            return Err(attention(
                "canonical timeline reported older content without a before cursor",
            ));
        };
        if previous_before.as_ref() == Some(&next) {
            return Err(attention(
                "canonical timeline before cursor did not advance",
            ));
        }
        previous_before = before.clone();
        before = Some(next);
    }
    Ok(locals)
}

fn hint_key(local: &str) -> String {
    format!("hint:{local}")
}

fn bot_input_id(bot_id: &str, chat_id: &str, message_id: &str) -> String {
    format!("bot:{bot_id}:{chat_id}:{message_id}")
}

fn interaction_hint() -> &'static str {
    "This turn is waiting for a local confirmation in the Studio desktop app. It cannot be approved from chat."
}

fn recoverable(diagnostic: impl Into<String>) -> InboundWorkOutcome {
    InboundWorkOutcome::Recoverable {
        diagnostic: diagnostic.into(),
    }
}

fn attention(diagnostic: impl Into<String>) -> InboundWorkOutcome {
    InboundWorkOutcome::NeedsAttention {
        diagnostic: diagnostic.into(),
    }
}

fn classify_send_error(error: FeishuError) -> InboundWorkOutcome {
    if error.retryable() {
        recoverable(error.to_string())
    } else {
        attention(error.to_string())
    }
}

/// 绑定链路的存储读写错误映射：保持错误自身 retryable 语义。
///
/// 不可恢复的坏行、归属冲突与坏记录转需处理，不再借 5s→300s 退避预算反复重试；
/// 真实暂时故障仍是可恢复重试。诊断只带安全类别，不带坏行原值。
fn binding_failure(context: &str, error: FeishuError) -> InboundWorkOutcome {
    if error.retryable() {
        recoverable(format!("{context}: {error}"))
    } else {
        attention(format!("{context}: {error}"))
    }
}

fn watch_error(context: &str, error: &str) -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        format!("{context}: {error}"),
        true,
        None,
    )
}

//! 入站受理后的正式自动回复：状态流只唤醒，结局从持久 canonical 事实重建。
//!
//! 首次进入、Lagged、观察重开与进程重启共用同一条恢复链：durable 输入路由/消费
//! 身份 → 原目标 Turn 的 typed 状态 → 交互终局事实。没有 active Turn 不等于原输入
//! 未执行；Absent 与 NotReady 分别表达，读/IO/decode 错误按分类退避而不是折叠成
//! 结局。等待循环与认领续约协调：观察者生命周期停止是 InboundWorkOutcome::Interrupted
//! （保留未决、释放认领为 pending），失租是 LostClaim（停止旧观察与新副作用）；
//! canonical Turn 的取消（含 Interrupted 原因）仍按真实取消结局收束。

use super::content::{FinalError, FinalText, collect_complete_turn_text, collect_preview};
use super::watch::ReplyWatch;

use crate::bots::InboundWorkOutcome;
use crate::bots::owner::BotRuntime;
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::bots::storage::card::{CardBinding, CardLifecycle, CardOperationStatus, CardStream};
use crate::bots::storage::{ClaimLease, FrozenInbound};
use crate::bots::{BotInputRead, BotTurnRead};
use crate::studio::StudioRuntime;
use pl_core::thread::input::{InputDelivery, InputState};
use pl_protocol::{TurnCompletion, TurnState};
use std::collections::BTreeSet;
use std::sync::Arc;
use std::sync::atomic::Ordering;
use std::time::Duration;
use tokio_util::sync::CancellationToken;

/// 认领续约节奏：60 秒租约内保留多次续约机会；等待本身不耗失败预算。
pub(super) const CLAIM_RENEW_INTERVAL: Duration = Duration::from_secs(15);
const PREVIEW_INTERVAL: Duration = Duration::from_millis(200);

/// 一次入站工作的恢复执行进度；`watch_input` 是当前 canonical 输入身份。
pub(super) struct ReplyRun {
    pub(super) bot_id: String,
    pub(super) chat_id: String,
    pub(super) message_id: String,
    pub(super) text: String,
    pub(super) attachments: Vec<crate::bots::inbound::InboundAttachment>,
    pub(super) worker_id: String,
    pub(super) thread_id: String,
    pub(super) original_input: String,
    pub(super) watch_input: String,
    /// 本执行内已受理的提示；真正的去重由发送账本的稳定操作身份保证。
    pub(super) hinted: BTreeSet<String>,
    pub(super) card: Option<CardStream>,
    pub(super) next_observation: tokio::time::Instant,
}

impl ReplyRun {
    pub(super) fn watching_original(&self) -> bool {
        self.watch_input == self.original_input
    }

    pub(super) fn card_binding(&self) -> CardBinding {
        CardBinding {
            bot_id: self.bot_id.clone(),
            chat_id: self.chat_id.clone(),
            message_id: self.message_id.clone(),
            thread_id: self.thread_id.clone(),
            original_input: self.original_input.clone(),
        }
    }
}

pub(super) enum Step {
    /// 已得出终局。
    Done(InboundWorkOutcome),
    /// 事实尚未就绪：等待流唤醒或下一轮续约重建。
    Wait,
    /// 本轮副作用已提交（首次 submit / continuation 切换），立即重建进度。
    Continue,
}

pub(super) enum ClaimGuard {
    Held,
    Lost,
}

/// The target is supplied by canonical input facts, never inferred from an old card.
#[derive(Clone, Copy)]
pub(super) enum ReplyTarget<'a> {
    Consumed(&'a str),
    Unconsumed,
}

impl<'a> ReplyTarget<'a> {
    pub(super) fn turn_id(self) -> Option<&'a str> {
        match self {
            Self::Consumed(turn_id) => Some(turn_id),
            Self::Unconsumed => None,
        }
    }
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
            attachments: inbound.attachments.clone(),
            worker_id: worker_id.to_string(),
            thread_id: String::new(),
            original_input: bot_input_id(&inbound.bot_id, &inbound.chat_id, &inbound.message_id),
            watch_input: if inbound.watch_input.is_empty() {
                bot_input_id(&inbound.bot_id, &inbound.chat_id, &inbound.message_id)
            } else {
                inbound.watch_input.clone()
            },
            hinted: BTreeSet::new(),
            card: None,
            next_observation: tokio::time::Instant::now(),
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
        if config.project_id != inbound.project_id || config.feishu().app_id != inbound.app_id {
            return attention("frozen inbound app or project no longer matches bot config");
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
        // A format upgrade must never reinterpret a historical text-send intent as
        // permission to create a new card, even when the old result is unknown.
        let binding = run.card_binding();
        match managed.store.load_send(&binding.reply_operation()).await {
            Ok(Some(record)) if record.bot_id == run.bot_id && record.chat_id == run.chat_id => {
                return if record.status == crate::bots::storage::SendRecordStatus::Succeeded {
                    InboundWorkOutcome::Completed
                } else {
                    attention(
                        "historical auto-reply send has a terminal or unknown result; it will not be resent as a card",
                    )
                };
            }
            Ok(Some(_)) => return attention("historical auto-reply send ownership conflicts"),
            Ok(None) => {}
            Err(error) => return classify_send_error(error),
        }
        run.card = match managed.store.load_card(&binding).await {
            Ok(card) => card,
            Err(error) => return classify_send_error(error),
        };
        if let Some(card) = run.card.as_mut() {
            if card.uncertain() || card.lifecycle == CardLifecycle::NeedsAttention {
                if let Some(operation) = card.last_operation.as_mut()
                    && operation.status == CardOperationStatus::Intent
                {
                    operation.status = CardOperationStatus::Unknown;
                    card.lifecycle = CardLifecycle::NeedsAttention;
                    match managed.store.save_card(card, worker_id).await {
                        Ok(crate::bots::storage::MarkOutcome::Applied) => {}
                        Ok(crate::bots::storage::MarkOutcome::LostClaim) => {
                            return InboundWorkOutcome::LostClaim;
                        }
                        Err(_) => {
                            return attention(
                                "unknown card operation recovery could not be persisted",
                            );
                        }
                    }
                }
                let diagnostic = card.diagnostic.as_ref().map_or_else(
                    || {
                        "card operation acceptance is unknown; automatic replay is disabled"
                            .to_string()
                    },
                    |diagnostic| {
                        format!(
                            "card requires local attention: {} (platform code {})",
                            diagnostic.message,
                            diagnostic.platform_code.as_deref().unwrap_or("none")
                        )
                    },
                );
                return attention(diagnostic);
            }
            if card.lifecycle.terminal() {
                return closed_card_outcome(card.lifecycle);
            }
        }
        let mut watch = match ReplyWatch::open(&runtime, &run.thread_id).await {
            Ok(watch) => watch,
            Err(error) => return classify_send_error(error),
        };
        loop {
            if cancel.is_cancelled() || self.inner.sealed.load(Ordering::SeqCst) != 0 {
                return InboundWorkOutcome::Interrupted;
            }
            tokio::select! {
                _ = cancel.cancelled() => return InboundWorkOutcome::Interrupted,
                _ = tokio::time::sleep_until(run.next_observation) => {}
            }
            run.next_observation = tokio::time::Instant::now() + PREVIEW_INTERVAL;
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

    pub(super) async fn renew_claim(&self, run: &ReplyRun) -> ClaimGuard {
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
            BotInputRead::NotReady => return Step::Wait,
            BotInputRead::Ready { delivery, state } => (delivery, state),
            BotInputRead::Absent => {
                if run.watching_original() {
                    return self.submit_original(runtime, run, cancel).await;
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
                self.finish_known_card(
                    run,
                    ReplyTarget::Unconsumed,
                    CardLifecycle::InteractionEnded,
                    cancel,
                )
                .await
            }
            (InputDelivery::NextTurn, InputState::Consumed { turn_id, .. }) => {
                self.advance_turn(runtime, run, &turn_id, cancel).await
            }
        }
    }

    /// 原输入尚未被 Studio 受理：以稳定身份排队，不打断或合并同会话的独立消息。
    /// 重复提交命中原受理事实，不重启已消费输入。
    async fn submit_original(
        &self,
        runtime: &StudioRuntime,
        run: &ReplyRun,
        cancel: &CancellationToken,
    ) -> Step {
        let drafts = match self
            .prepare_inbound_attachments(
                runtime,
                &run.bot_id,
                &run.thread_id,
                &run.message_id,
                &run.attachments,
                cancel,
            )
            .await
        {
            Ok(drafts) => drafts,
            Err(error) => {
                if cancel.is_cancelled() {
                    return Step::Done(InboundWorkOutcome::Interrupted);
                }
                return Step::Done(binding_failure(
                    "message attachment admission failed",
                    error,
                ));
            }
        };
        if cancel.is_cancelled() {
            for id in drafts {
                if let Err(error) = runtime.remove_attachment_draft(id).await {
                    tracing::warn!(%error, "failed to release cancelled bot attachment draft");
                }
            }
            return Step::Done(InboundWorkOutcome::Interrupted);
        }
        let result = runtime
            .submit_queued_prompt(crate::studio::StudioSubmitPromptRequest {
                thread_id: run.thread_id.clone(),
                input: pl_protocol::studio::StudioPromptInput {
                    input_id: run.original_input.clone(),
                    text: run.text.clone(),
                    attachment_draft_ids: drafts.clone(),
                },
                options: crate::studio::StudioSubmitPromptOptions::default(),
            })
            .await;
        for draft in drafts {
            if let Err(error) = runtime.remove_attachment_draft(draft).await {
                tracing::warn!(%error, "failed to release bot attachment draft");
            }
        }
        match result {
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
        // The caller already verified the canonical consumed-input -> Turn
        // identity. Persist it even if the Turn projection is not readable yet,
        // or the Turn terminates before producing its first preview.
        if let Err(outcome) = self
            .bind_reply_card_target(run, ReplyTarget::Consumed(turn_id))
            .await
        {
            return Step::Done(outcome);
        }
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
                match self
                    .hint_pending_interactions(runtime, run, turn_id, cancel)
                    .await
                {
                    Step::Wait => return Step::Wait,
                    Step::Done(outcome) => return Step::Done(outcome),
                    Step::Continue => {}
                }
                let preview = tokio::select! {
                    _ = cancel.cancelled() => return Step::Done(InboundWorkOutcome::Interrupted),
                    preview = collect_preview(runtime, &run.thread_id, turn_id) => preview,
                };
                let preview = match preview {
                    Ok(preview) => preview,
                    // A concurrent revision advance is expected while streaming;
                    // skip this preview and rebuild from canonical on the next wake.
                    Err(FinalError::Retryable(_)) => None,
                    Err(FinalError::Attention(diagnostic)) => {
                        return Step::Done(attention(diagnostic));
                    }
                };
                if let Err(outcome) = self
                    .progress_card(
                        run,
                        ReplyTarget::Consumed(turn_id),
                        preview.as_deref(),
                        CardLifecycle::Streaming,
                        cancel,
                    )
                    .await
                {
                    return Step::Done(outcome);
                }
                Step::Wait
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
            TurnState::Cancelled(_) => {
                self.finish_known_card(
                    run,
                    ReplyTarget::Consumed(turn_id),
                    CardLifecycle::Cancelled,
                    cancel,
                )
                .await
            }
            TurnState::Failed(_) => {
                self.finish_known_card(
                    run,
                    ReplyTarget::Consumed(turn_id),
                    CardLifecycle::Failed,
                    cancel,
                )
                .await
            }
            TurnState::BudgetLimited(_) => {
                self.finish_known_card(
                    run,
                    ReplyTarget::Consumed(turn_id),
                    CardLifecycle::BudgetLimited,
                    cancel,
                )
                .await
            }
        }
    }

    /// Turn 正常完成：完整 Final + Terminal 覆盖校验后，确认最后全文更新与关闭。
    async fn finish_with_final_text(
        &self,
        runtime: &StudioRuntime,
        run: &mut ReplyRun,
        turn_id: &str,
        cancel: &CancellationToken,
    ) -> Step {
        let collected = tokio::select! {
            _ = cancel.cancelled() => return Step::Done(InboundWorkOutcome::Interrupted),
            collected = collect_complete_turn_text(runtime, &run.thread_id, turn_id) => collected,
        };
        let text = match collected {
            Ok(FinalText::CompleteText(text)) => text,
            Ok(FinalText::CompleteNoText) => {
                return self
                    .finish_known_card(
                        run,
                        ReplyTarget::Consumed(turn_id),
                        CardLifecycle::NoFinalReply,
                        cancel,
                    )
                    .await;
            }
            Err(FinalError::Retryable(diagnostic)) => return Step::Done(recoverable(diagnostic)),
            Err(FinalError::Attention(diagnostic)) => return Step::Done(attention(diagnostic)),
        };
        if text.trim().is_empty() {
            return self
                .finish_known_card(
                    run,
                    ReplyTarget::Consumed(turn_id),
                    CardLifecycle::NoFinalReply,
                    cancel,
                )
                .await;
        }
        // 正文收集可能跨越续约窗口：正式发送前复核认领仍归本持有者。
        match self.renew_claim(run).await {
            ClaimGuard::Held => {}
            ClaimGuard::Lost => return Step::Done(InboundWorkOutcome::LostClaim),
        }
        match self
            .progress_card(
                run,
                ReplyTarget::Consumed(turn_id),
                Some(&text),
                CardLifecycle::Completed,
                cancel,
            )
            .await
        {
            Ok(()) => Step::Done(InboundWorkOutcome::Completed),
            Err(outcome) => Step::Done(outcome),
        }
    }

    pub(super) async fn finish_known_card(
        &self,
        run: &mut ReplyRun,
        target: ReplyTarget<'_>,
        lifecycle: CardLifecycle,
        cancel: &CancellationToken,
    ) -> Step {
        if run.card.is_none() {
            return Step::Done(InboundWorkOutcome::Completed);
        }
        match self
            .progress_card(run, target, None, lifecycle, cancel)
            .await
        {
            Ok(()) => Step::Done(closed_card_outcome(lifecycle)),
            Err(outcome) => Step::Done(outcome),
        }
    }

    /// 沿冻结绑定解析目标 Thread；归档、缺失与跨项目保持 NeedsAttention 语义。
    async fn resolve_bound_thread(
        &self,
        managed: &Arc<crate::bots::owner::ManagedBot>,
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
            crate::bots::storage::ThreadBindingClaim::Bound { thread_id, .. } => thread_id,
            crate::bots::storage::ThreadBindingClaim::Creating { creation_id, .. } => {
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
            crate::bots::storage::ThreadBindingClaim::NeedsAttention { diagnostic } => {
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

fn closed_card_outcome(lifecycle: CardLifecycle) -> InboundWorkOutcome {
    if lifecycle == CardLifecycle::NoFinalReply {
        return attention(lifecycle.summary());
    }
    InboundWorkOutcome::Completed
}

pub(super) fn hint_key(local: &str) -> String {
    format!("hint:{local}")
}

pub(super) fn bot_input_id(bot_id: &str, chat_id: &str, message_id: &str) -> String {
    format!("bot:{bot_id}:{chat_id}:{message_id}")
}

pub(super) fn interaction_hint() -> &'static str {
    "This turn is waiting for a local confirmation in the Studio desktop app. It cannot be approved from chat."
}

pub(super) fn recoverable(diagnostic: impl Into<String>) -> InboundWorkOutcome {
    InboundWorkOutcome::Recoverable {
        diagnostic: diagnostic.into(),
    }
}

pub(super) fn attention(diagnostic: impl Into<String>) -> InboundWorkOutcome {
    InboundWorkOutcome::NeedsAttention {
        diagnostic: diagnostic.into(),
    }
}

pub(super) fn classify_send_error(error: FeishuError) -> InboundWorkOutcome {
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
pub(super) fn binding_failure(context: &str, error: FeishuError) -> InboundWorkOutcome {
    if error.retryable() {
        recoverable(format!("{context}: {error}"))
    } else {
        attention(format!("{context}: {error}"))
    }
}

pub(super) fn watch_error(context: &str, error: &str) -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        format!("{context}: {error}"),
        true,
        None,
    )
}

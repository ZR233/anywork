//! 入站受理后的正式自动回复：同源增量维护 Final，结局从可靠 canonical 事实核对。
//!
//! 首次进入、Lagged、观察重开与进程重启共用同一条恢复链：durable 输入路由/消费
//! 身份 → 原目标 Turn 的 typed 状态 → 交互终局事实。没有 active Turn 不等于原输入
//! 未执行；Absent 与 NotReady 分别表达，读/IO/decode 错误按分类退避而不是折叠成
//! 结局。等待循环与认领续约协调：观察者生命周期停止是 InboundWorkOutcome::Interrupted
//! （保留未决、释放认领为 pending），失租是 LostClaim（停止旧观察与新副作用）；
//! canonical Turn 的取消（含 Interrupted 原因）仍按真实取消结局收束。

use super::content::{FinalError, FinalText, collect_complete_turn_text};
use super::watch::ReplyWatch;

use crate::bots::BotInputRead;
use crate::bots::InboundWorkOutcome;
use crate::bots::owner::BotRuntime;
use crate::bots::protocol::error::FeishuError;
use crate::bots::storage::card::{CardBinding, CardLifecycle, CardOperationStatus, CardStream};
use crate::bots::storage::{ClaimLease, FrozenInbound};
use crate::studio::{StudioRuntime, TimelineContentReader};
use pl_core::thread::input::{InputDelivery, InputState};
use pl_protocol::{TimelineTurnOutcome, TurnCompletion, TurnState};
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

struct ReplyContent<'a> {
    reader: &'a TimelineContentReader,
    preview: Option<&'a str>,
    observed: Option<TurnState>,
    terminal: Option<TimelineTurnOutcome>,
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
        registered_thread_id: &str,
        cancel: CancellationToken,
    ) -> InboundWorkOutcome {
        // 整个 dispatch（含初始绑定解析、观察打开、屏障、翻页、submit、发送等全部
        // 长 await）与 ≤20s 的认领续约在同一 JoinSet 任务内结构化并发：heartbeat
        // 失租先取消主执行，再等它排空已启动的文件 I/O 与可靠发送交接，最后返回
        // LostClaim，不覆盖后继持有者的账本。所有副作用仍使用原稳定身份核实，
        // 不把受理未知解释为未发生。cancel 由主执行自身收束；heartbeat 在 cancel 后
        // 挂起，不会把 runtime 停止误报成失租。
        let heartbeat_keys = (
            inbound.bot_id.clone(),
            inbound.chat_id.clone(),
            inbound.message_id.clone(),
        );
        let heartbeat_worker = worker_id.to_string();
        // The same reply owns every started operation until its real completion,
        // including on lease loss. No detached successor or cleanup task.
        let reply_cancel = cancel.child_token();
        let mut reply = Box::pin(self.run_reply(
            inbound,
            worker_id,
            registered_thread_id,
            reply_cancel.clone(),
        ));
        tokio::select! {
        outcome = &mut reply => outcome,
        // heartbeat 只会因失租完成；cancel 后它保持挂起，不误报 runtime 停止。
        _ = heartbeat_claims(self.clone(), heartbeat_keys, heartbeat_worker, cancel.clone()) => {
                reply_cancel.cancel();
                let _ = reply.await;
                InboundWorkOutcome::LostClaim
            }
        }
    }

    async fn run_reply(
        &self,
        inbound: FrozenInbound,
        worker_id: &str,
        registered_thread_id: &str,
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
        if config.workspace_id != inbound.workspace_id || config.feishu().app_id != inbound.app_id {
            return attention("frozen inbound app or project no longer matches bot config");
        }
        // 冻结路由：入站受理时的 App/project/creation/binding 归属不因新配置改派。
        let resolved = tokio::select! {
            _ = cancel.cancelled() => return InboundWorkOutcome::Interrupted,
            resolved = self.resolve_bound_thread(
                &managed, &runtime, &inbound, inbound.binding_revision
            ) => resolved,
        };
        let thread_id = match resolved {
            Ok(thread_id) => thread_id,
            Err(outcome) => return outcome,
        };
        if thread_id != registered_thread_id {
            return attention("resolved bot Thread differs from registered reply owner");
        }
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
        let opened = tokio::select! {
            _ = cancel.cancelled() => return InboundWorkOutcome::Interrupted,
            opened = ReplyWatch::open(&runtime, &run.thread_id) => opened,
        };
        let mut watch = match opened {
            Ok(watch) => watch,
            Err(error) => return content_failure(error),
        };
        // At most one in-place resume; subsequent failures follow the existing retryable
        // inbound-work policy. No platform action is replayed by this recovery.
        let mut resumed = false;
        let outcome = loop {
            if cancel.is_cancelled() || self.inner.sealed.load(Ordering::SeqCst) != 0 {
                break InboundWorkOutcome::Interrupted;
            }
            let observed = tokio::select! {
                _ = cancel.cancelled() => break InboundWorkOutcome::Interrupted,
                event = watch.receive() => Some(event),
                _ = tokio::time::sleep_until(run.next_observation) => None,
            };
            if let Some(observed) = observed {
                if let Err(error) = observed {
                    if !resumed && matches!(error, FinalError::Retryable(_)) {
                        resumed = true;
                        let result = tokio::select! {
                            _ = cancel.cancelled() => break InboundWorkOutcome::Interrupted,
                            result = watch.reconnect(&runtime) => result,
                        };
                        if let Err(error) = result {
                            break content_failure(error);
                        }
                        continue;
                    }
                    break content_failure(error);
                }
                continue;
            }
            let renewed = tokio::select! {
                _ = cancel.cancelled() => break InboundWorkOutcome::Interrupted,
                renewed = watch.during(self.renew_claim(&run), None) => renewed,
            };
            match renewed {
                (ClaimGuard::Lost, _) => break InboundWorkOutcome::LostClaim,
                (_, Some(error)) => break content_failure(error),
                (ClaimGuard::Held, None) => {}
            }
            // Cancellation is checked inside each action before intent; a
            // committed HTTP request is drained and confirmed even on shutdown.
            // The heap boundary keeps the nested action state out of this long-lived
            // owner future without changing its cancellation or drop behavior.
            let step = Box::pin(self.advance(&runtime, &mut run, &mut watch, &cancel)).await;
            // Sending and receiving have independent clocks. Pending updates are
            // reduced throughout the window, including waits inside advance.
            run.next_observation = tokio::time::Instant::now() + PREVIEW_INTERVAL;
            match step {
                Step::Done(outcome) => break outcome,
                Step::Continue => {
                    // A continuation invalidates the old projection immediately;
                    // the next canonical input receipt selects its actual Turn.
                    let reset = tokio::select! {
                        _ = cancel.cancelled() => break InboundWorkOutcome::Interrupted,
                        reset = watch.select_target(&runtime, &run.watch_input, None) => reset,
                    };
                    if let Err(error) = reset {
                        break content_failure(error);
                    }
                }
                Step::Wait => {}
            }
        };
        if let Err(error) = watch.close().await {
            if !matches!(
                outcome,
                InboundWorkOutcome::LostClaim | InboundWorkOutcome::Interrupted
            ) {
                return content_failure(error);
            }
            tracing::warn!("reply observation close failed during owner retirement");
        }
        outcome
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
        watch: &mut ReplyWatch,
        cancel: &CancellationToken,
    ) -> Step {
        let covered = tokio::select! {
            _ = cancel.cancelled() => return Step::Done(InboundWorkOutcome::Interrupted),
            covered = watch.ensure_coverage() => covered,
        };
        if let Err(error) = covered {
            return Step::Done(content_failure(error));
        }
        let input = tokio::select! {
            _ = cancel.cancelled() => return Step::Done(InboundWorkOutcome::Interrupted),
            input = Box::pin(watch.during(runtime.bot_input_fact(&run.thread_id, &run.watch_input), None)) => input,
        };
        let input = match input {
            (_, Some(error)) => return Step::Done(content_failure(error)),
            (input, None) => input,
        };
        let input = match input {
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
                    let action_cancel = cancel.child_token();
                    return observed_step(
                        Box::pin(watch.during(
                            self.submit_original(runtime, run, &action_cancel),
                            Some(&action_cancel),
                        ))
                        .await,
                        cancel,
                    );
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
                let action_cancel = cancel.child_token();
                observed_step(
                    Box::pin(watch.during(
                        self.finish_known_card(
                            run,
                            ReplyTarget::Unconsumed,
                            CardLifecycle::InteractionEnded,
                            &action_cancel,
                        ),
                        Some(&action_cancel),
                    ))
                    .await,
                    cancel,
                )
            }
            (InputDelivery::NextTurn, InputState::Consumed { turn_id, .. }) => {
                let selected = tokio::select! {
                    _ = cancel.cancelled() => return Step::Done(InboundWorkOutcome::Interrupted),
                    selected = watch.select_target(runtime, &run.watch_input, Some(&turn_id)) => selected,
                };
                if let Err(error) = selected {
                    return Step::Done(content_failure(error));
                }
                let reader = watch.reader();
                let preview = watch.preview();
                let observed = watch.observed_state(&turn_id);
                let terminal = watch.terminal(&turn_id);
                let action_cancel = cancel.child_token();
                observed_step(
                    Box::pin(watch.during(
                        self.advance_turn(
                            runtime,
                            run,
                            &turn_id,
                            ReplyContent {
                                reader: &reader,
                                preview: preview.as_deref(),
                                observed,
                                terminal,
                            },
                            &action_cancel,
                        ),
                        Some(&action_cancel),
                    ))
                    .await,
                    cancel,
                )
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
        // Media preparation owns and drains started file work. Its admission
        // boundary observes cancellation without dropping the whole operation.
        let prepared = self
            .prepare_inbound_attachments(
                runtime,
                &run.bot_id,
                &run.thread_id,
                &run.message_id,
                &run.attachments,
                cancel,
            )
            .await;
        let drafts = match prepared {
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
        let request = crate::studio::StudioSubmitPromptRequest {
            thread_id: run.thread_id.clone(),
            input: pl_protocol::studio::StudioPromptInput {
                input_id: run.original_input.clone(),
                text: run.text.clone(),
                attachment_draft_ids: drafts.clone(),
            },
            options: crate::studio::StudioSubmitPromptOptions::default(),
        };
        // Only the runtime's admission wait may be cancelled. Once it starts
        // retaining resources or submitting the stable input, keep this future
        // and its drafts alive until their real result has been acknowledged.
        let result = runtime.submit_queued_prompt(request, cancel).await;
        for draft in drafts {
            if let Err(error) = runtime.remove_attachment_draft(draft).await {
                tracing::warn!(%error, "failed to release bot attachment draft");
            }
        }
        match result {
            // 受理后首个 effect 落库前身份仍可能 Absent；等待唤醒后重建，不连续重提。
            Ok(_) => Step::Wait,
            Err(_) if cancel.is_cancelled() => Step::Done(InboundWorkOutcome::Interrupted),
            Err(error) => Step::Done(recoverable(format!("bot prompt submit failed: {error:#}"))),
        }
    }

    async fn advance_turn(
        &self,
        runtime: &StudioRuntime,
        run: &mut ReplyRun,
        turn_id: &str,
        content: ReplyContent<'_>,
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
        match content.terminal {
            None if matches!(
                content.observed,
                Some(TurnState::Queued(_) | TurnState::Running(_))
            ) =>
            {
                match self
                    .hint_pending_interactions(runtime, run, turn_id, cancel)
                    .await
                {
                    Step::Wait => return Step::Wait,
                    Step::Done(outcome) => return Step::Done(outcome),
                    Step::Continue => {}
                }
                if let Err(outcome) = self
                    .progress_card(
                        run,
                        ReplyTarget::Consumed(turn_id),
                        content.preview,
                        CardLifecycle::Streaming,
                        cancel,
                    )
                    .await
                {
                    return Step::Done(outcome);
                }
                Step::Wait
            }
            None => Step::Wait,
            Some(TimelineTurnOutcome::Completed(state)) => match state.completion() {
                TurnCompletion::Normal => {
                    self.finish_with_final_text(runtime, run, turn_id, content.reader, cancel)
                        .await
                }
                TurnCompletion::InteractionRequested => {
                    self.advance_interactions(runtime, run, turn_id, content.reader, cancel)
                        .await
                }
            },
            Some(TimelineTurnOutcome::Cancelled(_)) => {
                self.finish_known_card(
                    run,
                    ReplyTarget::Consumed(turn_id),
                    CardLifecycle::Cancelled,
                    cancel,
                )
                .await
            }
            Some(TimelineTurnOutcome::Failed(_)) => {
                self.finish_known_card(
                    run,
                    ReplyTarget::Consumed(turn_id),
                    CardLifecycle::Failed,
                    cancel,
                )
                .await
            }
            Some(TimelineTurnOutcome::BudgetLimited(_)) => {
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
        reader: &TimelineContentReader,
        cancel: &CancellationToken,
    ) -> Step {
        let collected = tokio::select! {
            _ = cancel.cancelled() => return Step::Done(InboundWorkOutcome::Interrupted),
            collected = collect_complete_turn_text(runtime, reader, turn_id) => collected,
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
        match runtime.find_owned_thread(&thread_id).await {
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

pub(super) fn content_failure(error: FinalError) -> InboundWorkOutcome {
    match error {
        FinalError::Retryable(diagnostic) => recoverable(diagnostic),
        FinalError::Attention(diagnostic) => attention(diagnostic),
    }
}

fn observed_step((step, failure): (Step, Option<FinalError>), cancel: &CancellationToken) -> Step {
    if matches!(step, Step::Done(InboundWorkOutcome::LostClaim)) {
        return step;
    }
    if cancel.is_cancelled() {
        return Step::Done(InboundWorkOutcome::Interrupted);
    }
    match failure {
        Some(error) => Step::Done(content_failure(error)),
        None => step,
    }
}

#[cfg(test)]
mod archive_cancellation_tests {
    use super::*;
    use crate::bots::commands::archive_tests::Fixture;
    use crate::bots::inbound::InboundAttachment;

    #[tokio::test]
    async fn media_setup_and_prompt_admission_exit_the_owned_reply_on_cancel() -> anyhow::Result<()>
    {
        let fixture = Fixture::new().await?;
        let inbound = fixture.inbound("cancel-admission", true).await?;
        let managed = fixture.bots.managed(&inbound.bot_id).await?;
        for media in [false, true] {
            let mut run = ReplyRun {
                bot_id: inbound.bot_id.clone(),
                chat_id: inbound.chat_id.clone(),
                message_id: inbound.message_id.clone(),
                text: inbound.text.clone(),
                attachments: Vec::new(),
                worker_id: "fixture-worker".into(),
                thread_id: inbound.creation_id.clone(),
                original_input: bot_input_id(
                    &inbound.bot_id,
                    &inbound.chat_id,
                    &inbound.message_id,
                ),
                watch_input: String::new(),
                hinted: BTreeSet::new(),
                card: None,
                next_observation: tokio::time::Instant::now(),
            };
            if media {
                run.attachments.push(InboundAttachment::Image {
                    key: "isolated-media-key".into(),
                });
            }
            // With media, hold its config lookup before token/network work;
            // without media, the real queued-submit waits on lifecycle_lock.
            let lifecycle = fixture.host.lifecycle_lock().lock().await;
            let config = if media {
                Some(managed.config.lock().await)
            } else {
                None
            };
            let cancel = fixture.bots.inner.reply_cancel.child_token();
            let action = fixture
                .bots
                .submit_original(&fixture.host.runtime, &run, &cancel);
            tokio::pin!(action);
            assert!(futures::poll!(&mut action).is_pending());
            cancel.cancel();
            assert!(matches!(
                tokio::time::timeout(Duration::from_secs(5), action).await?,
                Step::Done(InboundWorkOutcome::Interrupted)
            ));
            assert!(!fixture.bots.inner.reply_cancel.is_cancelled());
            drop(config);
            drop(lifecycle);
            assert_eq!(
                fixture
                    .host
                    .runtime
                    .bot_input_fact(&run.thread_id, &run.original_input,)
                    .await?,
                BotInputRead::Absent,
            );
        }
        fixture.shutdown().await
    }
}

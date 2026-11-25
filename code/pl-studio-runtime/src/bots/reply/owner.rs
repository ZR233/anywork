//! 入站受理后的正式自动回复：同源增量维护 Final，结局从可靠 canonical 事实核对。
//!
//! 首次进入、Lagged、观察重开与进程重启共用同一条恢复链：durable 输入路由/消费
//! 身份 → 原目标 Turn 的 typed 状态 → 交互终局事实。没有 active Turn 不等于原输入
//! 未执行；Absent 与 NotReady 分别表达，读/IO/decode 错误按分类退避而不是折叠成
//! 结局。等待循环与认领续约协调：观察者生命周期停止是 InboundWorkOutcome::Interrupted
//! （保留未决、释放认领为 pending），失租是 LostClaim（停止旧观察与新副作用）；
//! canonical Turn 的取消（含 Interrupted 原因）仍按真实取消结局收束。

use super::content::{FinalError, FinalText, collect_complete_turn_text};
use super::lease::{ClaimGuard, ClaimLeaseGuard};
use super::projection::ReplyProjection;
use super::session::{ReplyInputAction, ReplySession, ReplyTarget, ReplyTurnAction, Step};
use super::watch::ReplyWatch;

use crate::TurnState;
use crate::bots::InboundWorkOutcome;
use crate::bots::owner::BotRuntime;
use crate::bots::protocol::error::FeishuError;
use crate::bots::storage::FrozenInbound;
use crate::bots::storage::card::{CardLifecycle, CardOperationStatus};
use crate::studio::StudioRuntime;
use std::sync::atomic::Ordering;
use std::time::Duration;
use tokio_util::sync::CancellationToken;

const PREVIEW_INTERVAL: Duration = Duration::from_millis(200);

struct ReplyContent<'a> {
    projection: Option<&'a ReplyProjection>,
    active: bool,
    preview: Option<&'a str>,
    observed: Option<TurnState>,
    terminal: Option<TurnState>,
}

impl BotRuntime {
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
        let lease = ClaimLeaseGuard::new(self.clone(), &inbound, worker_id);
        let reply_cancel = cancel.child_token();
        let mut reply = Box::pin(self.run_reply(
            inbound,
            worker_id,
            registered_thread_id,
            reply_cancel.clone(),
        ));
        tokio::select! {
            outcome = &mut reply => outcome,
            _ = lease.until_lost(&cancel) => {
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
        let run = ReplySession::new(self.clone(), &inbound, worker_id);
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
        run.file_delivery_diagnostic = run
            .card
            .as_ref()
            .and_then(|card| card.file_delivery_diagnostic.clone());
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
                if let Some(diagnostic) = &card.file_delivery_diagnostic {
                    return attention(diagnostic.clone());
                }
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

    /// 一轮 canonical 重建：输入路由 → 目标 Turn → 交互终局。
    async fn advance(
        &self,
        runtime: &StudioRuntime,
        run: &mut ReplySession,
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
            input = Box::pin(watch.during(
                std::future::ready(runtime.bot_input_fact(&run.thread_id, &run.watch_input)),
                None,
            )) => input,
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
        match run.reconcile_input(input) {
            ReplyInputAction::SubmitOriginal => {
                let action_cancel = cancel.child_token();
                observed_step(
                    Box::pin(watch.during(
                        self.submit_original(runtime, run, &action_cancel),
                        Some(&action_cancel),
                    ))
                    .await,
                    cancel,
                )
            }
            ReplyInputAction::ConcurrentTurn => {
                Step::Done(attention("bot input was routed onto a concurrent turn"))
            }
            ReplyInputAction::Wait => Step::Wait,
            ReplyInputAction::FinishUnconsumed => {
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
            ReplyInputAction::ObserveTurn(turn_id) => {
                let selected = tokio::select! {
                    _ = cancel.cancelled() => return Step::Done(InboundWorkOutcome::Interrupted),
                    selected = watch.select_target(runtime, &run.watch_input, Some(&turn_id)) => selected,
                };
                if let Err(error) = selected {
                    return Step::Done(content_failure(error));
                }
                let preview = watch.preview();
                let observed = watch.observed_state(&turn_id);
                let terminal = watch.terminal(&turn_id);
                let projection = watch.projection();
                let action_cancel = cancel.child_token();
                observed_step(
                    Box::pin(watch.during(
                        self.advance_turn(
                            runtime,
                            run,
                            &turn_id,
                            ReplyContent {
                                projection: projection.as_ref(),
                                active: projection.as_ref().is_some_and(ReplyProjection::active),
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
        run: &ReplySession,
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
            input: crate::StudioPromptInput {
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
        run: &mut ReplySession,
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
        // A live terminal is only a hint. Every terminal platform transition,
        // including failure/cancel and interaction pause, requires the original
        // explicit save barrier and completed-message/body coverage first.
        let verified = if content.terminal.is_some() {
            let Some(projection) = content.projection else {
                return Step::Wait;
            };
            // 收集是同步的：`std::future::ready(..)` 会在轮询取消之前就完成全部工作，
            // 因此先判定取消，再直接收集。
            if cancel.is_cancelled() {
                return Step::Done(InboundWorkOutcome::Interrupted);
            }
            match collect_complete_turn_text(projection) {
                Ok(text) => Some(text),
                Err(error) => return Step::Done(content_failure(error)),
            }
        } else {
            None
        };
        if let Some(projection) = content.projection
            && let Err(outcome) =
                super::files::deliver_file_displays(runtime, run, turn_id, projection, cancel).await
        {
            return Step::Done(outcome);
        }
        let step = match ReplyTurnAction::for_snapshot(
            content.terminal.as_ref(),
            content.observed.as_ref(),
            content.active,
        ) {
            ReplyTurnAction::Preview => {
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
            ReplyTurnAction::Wait => Step::Wait,
            ReplyTurnAction::FinishText => {
                self.finish_with_final_text(
                    run,
                    turn_id,
                    verified.expect("verified terminal"),
                    cancel,
                )
                .await
            }
            ReplyTurnAction::AwaitInteraction => {
                self.advance_interactions(
                    runtime,
                    run,
                    turn_id,
                    content.projection.expect("verified projection"),
                    cancel,
                )
                .await
            }
            ReplyTurnAction::Close(lifecycle) => {
                self.finish_known_card(run, ReplyTarget::Consumed(turn_id), lifecycle, cancel)
                    .await
            }
        };
        run.settle(step)
    }

    /// Turn 正常完成：完整 Final + Terminal 覆盖校验后，确认最后全文更新与关闭。
    async fn finish_with_final_text(
        &self,
        run: &mut ReplySession,
        turn_id: &str,
        collected: FinalText,
        cancel: &CancellationToken,
    ) -> Step {
        let text = match collected {
            FinalText::CompleteText(text) => text,
            FinalText::CompleteNoText => {
                return self
                    .finish_known_card(
                        run,
                        ReplyTarget::Consumed(turn_id),
                        CardLifecycle::NoFinalReply,
                        cancel,
                    )
                    .await;
            }
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
        run: &mut ReplySession,
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

pub(super) fn interaction_hint() -> &'static str {
    "This turn is waiting for a local confirmation in the Studio desktop app. It cannot be approved from chat."
}

pub(in crate::bots) fn recoverable(diagnostic: impl Into<String>) -> InboundWorkOutcome {
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
pub(in crate::bots) fn binding_failure(context: &str, error: FeishuError) -> InboundWorkOutcome {
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
    use super::super::session::bot_input_id;
    use super::*;
    use crate::bots::inbound::InboundAttachment;
    use crate::bots::storage::card::{CardBinding, CardStream};
    use crate::bots::test_support::Fixture;
    use std::collections::BTreeSet;

    #[tokio::test]
    async fn completed_card_recovery_keeps_independent_file_delivery_failure() -> anyhow::Result<()>
    {
        use crate::bots::storage::card::{CardAction, CardOperationStatus, hash};
        use crate::bots::storage::{InboundClaim, MarkOutcome};
        let fixture = Fixture::new().await?;
        let inbound = fixture.inbound("closed-card-file-failure", true).await?;
        let managed = fixture.bots.managed(&inbound.bot_id).await?;
        let worker = "file-recovery-worker";
        assert_eq!(
            managed
                .store
                .claim_inbound_work(
                    &inbound.bot_id,
                    &inbound.chat_id,
                    &inbound.message_id,
                    worker
                )
                .await?,
            InboundClaim::Claimed
        );
        let original = bot_input_id(&inbound.bot_id, &inbound.chat_id, &inbound.message_id);
        let binding = CardBinding {
            bot_id: inbound.bot_id.clone(),
            chat_id: inbound.chat_id.clone(),
            message_id: inbound.message_id.clone(),
            thread_id: inbound.creation_id.clone(),
            original_input: original.clone(),
        };
        let mut card = CardStream::new(binding, &original, "finished-turn");
        card.card_id = Some("confirmed-card".into());
        card.platform_message_id = Some("confirmed-card-message".into());
        card.confirmed_text = "Final text delivered independently".into();
        card.confirmed_content_hash = hash(card.confirmed_text.as_bytes());
        card.final_content_hash = Some(card.confirmed_content_hash.clone());
        card.reserve(CardAction::Settings {
            streaming: false,
            lifecycle: CardLifecycle::Completed,
            recovery: false,
        })?;
        card.last_operation.as_mut().unwrap().status = CardOperationStatus::Confirmed;
        card.confirmed_sequence = card.sequence;
        card.lifecycle = CardLifecycle::Completed;
        card.file_delivery_diagnostic = Some("file message acceptance is unknown".into());
        assert_eq!(
            managed.store.save_card(&mut card, worker).await?,
            MarkOutcome::Applied
        );
        // run_reply reloads the durable card before any network or new content subscription.
        let thread_id = inbound.creation_id.clone();
        let outcome = fixture
            .bots
            .run_reply(inbound, worker, &thread_id, CancellationToken::new())
            .await;
        assert_eq!(
            outcome,
            InboundWorkOutcome::NeedsAttention {
                diagnostic: "file message acceptance is unknown".into(),
            }
        );
        fixture.shutdown().await
    }

    #[tokio::test]
    async fn media_setup_and_prompt_admission_exit_the_owned_reply_on_cancel() -> anyhow::Result<()>
    {
        let fixture = Fixture::new().await?;
        let inbound = fixture.inbound("cancel-admission", true).await?;
        let managed = fixture.bots.managed(&inbound.bot_id).await?;
        for media in [false, true] {
            let mut run = ReplySession {
                output: crate::bots::files::feishu_reply_binding(
                    fixture.bots.clone(),
                    &inbound,
                    "fixture-worker",
                ),
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
                delivered_displays: BTreeSet::new(),
                file_delivery_diagnostic: None,
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
            let cancel = fixture.bots.inner.reply_work.cancel.child_token();
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
            assert!(!fixture.bots.inner.reply_work.cancel.is_cancelled());
            drop(config);
            drop(lifecycle);
            assert_eq!(
                fixture
                    .host
                    .runtime
                    .bot_input_fact(&run.thread_id, &run.original_input)?,
                BotInputRead::Absent,
            );
        }
        fixture.shutdown().await
    }
}

#[cfg(test)]
mod tests;

#[cfg(test)]
mod identity;

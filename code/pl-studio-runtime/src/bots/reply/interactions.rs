use super::content::MAX_TURN_CONTENT_ITEMS;
use super::owner::ReplyTarget;
use super::owner::{
    ClaimGuard, ReplyRun, Step, attention, hint_key, interaction_hint, recoverable,
};
use crate::bots::InboundWorkOutcome;
use crate::bots::owner::BotRuntime;
use crate::bots::storage::{MarkOutcome, card::CardLifecycle};
use crate::bots::{BotInteractionKind, BotInteractionRead, SendAuthority};
use crate::studio::StudioRuntime;
use pl_protocol::InteractionStatus;
use pl_protocol::{ThreadItemKind, ThreadItemState, TimelinePageQuery};
use std::collections::BTreeSet;
use tokio_util::sync::CancellationToken;

/// timeline 兜底：快照不再保留该 Turn 的交互时，从 tool.user_input 投影发现 local 身份。
pub(super) async fn discover_timeline_interactions(
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

impl BotRuntime {
    /// Turn 以交互请求收尾：边界终局只由 UserInput 类交互决定。
    ///
    /// 权限记录与 UserInput 交互共存于同一 Turn 的快照（core 驻留保留 settled
    /// permission record）：已决议权限只说明原 Turn 曾恢复执行，Allowed/Denied 都
    /// 不构成此边界的结局，跳过而不终结整个工作；Pending 权限仍等待并提示。
    /// 无法得出任何 UserInput 终局时保持待定，不把只含已决议权限的集合当错误终结。
    pub(super) async fn advance_interactions(
        &self,
        runtime: &StudioRuntime,
        run: &mut ReplyRun,
        turn_id: &str,
        cancel: &CancellationToken,
    ) -> Step {
        if let Err(outcome) = self
            .progress_card(
                run,
                ReplyTarget::Consumed(turn_id),
                None,
                CardLifecycle::Paused,
                cancel,
            )
            .await
        {
            return Step::Done(outcome);
        }
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
                                None => {
                                    self.finish_known_card(
                                        run,
                                        ReplyTarget::Consumed(turn_id),
                                        CardLifecycle::InteractionEnded,
                                        cancel,
                                    )
                                    .await
                                }
                            };
                        }
                        InteractionStatus::Cancelled | InteractionStatus::Expired => {
                            return self
                                .finish_known_card(
                                    run,
                                    ReplyTarget::Consumed(turn_id),
                                    CardLifecycle::InteractionEnded,
                                    cancel,
                                )
                                .await;
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
    pub(super) async fn hint_pending_interactions(
        &self,
        runtime: &StudioRuntime,
        run: &mut ReplyRun,
        turn_id: &str,
        cancel: &CancellationToken,
    ) -> Step {
        // Running Turns use only the current canonical interaction snapshot. Cold
        // timeline discovery is for terminal recovery, not an O(history) token path.
        let snapshot = match runtime.thread_snapshot(&run.thread_id).await {
            Ok(snapshot) => snapshot,
            Err(_) => {
                return Step::Done(recoverable("canonical interaction snapshot is not ready"));
            }
        };
        let locals: BTreeSet<String> = snapshot
            .interactions
            .iter()
            .filter(|interaction| interaction.scope.turn_id == turn_id)
            .filter_map(|interaction| {
                crate::thread_assembler::decode_interaction_key(&interaction.interaction_id)
                    .ok()
                    .map(|(_, local)| local.to_string())
            })
            .collect();
        let mut waiting = false;
        for local in &locals {
            let pending = match runtime.bot_interaction_fact(&run.thread_id, local).await {
                Ok(BotInteractionRead::Ready(fact)) => {
                    if fact.kind == BotInteractionKind::UserInput
                        && fact.status != InteractionStatus::Pending
                    {
                        // Only the terminal interaction recovery path may bind
                        // canonical continuation. A stale Running Turn cannot
                        // reopen its old preview after a local input decision.
                        waiting = true;
                    }
                    fact.status == InteractionStatus::Pending
                }
                Ok(BotInteractionRead::NotReady | BotInteractionRead::Absent) => {
                    waiting = true;
                    false
                }
                Err(_) => {
                    return Step::Done(recoverable("canonical interaction fact is not readable"));
                }
            };
            if pending {
                waiting = true;
                if let Err(outcome) = self
                    .progress_card(
                        run,
                        ReplyTarget::Consumed(turn_id),
                        None,
                        CardLifecycle::Paused,
                        cancel,
                    )
                    .await
                {
                    return Step::Done(outcome);
                }
                match self.send_interaction_hint(run, local).await {
                    Step::Done(outcome) => return Step::Done(outcome),
                    Step::Wait | Step::Continue => {}
                }
            }
        }
        if waiting { Step::Wait } else { Step::Continue }
    }

    async fn send_interaction_hint(&self, run: &mut ReplyRun, local: &str) -> Step {
        let key = hint_key(local);
        if run.hinted.contains(&key) {
            return Step::Wait;
        }
        if matches!(self.renew_claim(run).await, ClaimGuard::Lost) {
            return Step::Done(InboundWorkOutcome::LostClaim);
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
                SendAuthority::AutoReply,
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
}

//! Inbound reply progress and its canonical input and Turn identity.
use crate::bots::{
    BotInputRead, InboundWorkOutcome,
    owner::BotRuntime,
    storage::{
        FrozenInbound,
        card::{CardBinding, CardLifecycle, CardStream},
    },
};
use crate::{TurnCompletion, TurnState};
use pl_core::thread::input::InputState;
use std::collections::BTreeSet;

/// 一次入站工作的恢复执行进度；`watch_input` 是当前 canonical 输入身份。
pub(super) struct ReplySession {
    pub(super) output: crate::channel_output::ChannelOutputBinding,
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
    pub(super) delivered_displays: BTreeSet<String>,
    pub(super) file_delivery_diagnostic: Option<String>,
    pub(super) card: Option<CardStream>,
    pub(super) next_observation: tokio::time::Instant,
}

impl ReplySession {
    pub(super) fn reconcile_input(&self, input: BotInputRead) -> ReplyInputAction {
        match input {
            BotInputRead::Absent if self.watch_input == self.original_input => {
                ReplyInputAction::SubmitOriginal
            }
            BotInputRead::Absent
            | BotInputRead::Ready {
                state: InputState::Pending,
            } => ReplyInputAction::Wait,
            BotInputRead::Ready {
                state: InputState::Discarded,
            } => ReplyInputAction::FinishUnconsumed,
            BotInputRead::Ready {
                state: InputState::Consumed { turn_id, .. },
            } => ReplyInputAction::ObserveTurn(turn_id),
        }
    }

    pub(super) fn settle(&self, step: Step) -> Step {
        match (step, &self.file_delivery_diagnostic) {
            (Step::Done(InboundWorkOutcome::Completed), Some(diagnostic)) => {
                Step::Done(InboundWorkOutcome::NeedsAttention {
                    diagnostic: diagnostic.clone(),
                })
            }
            (step, _) => step,
        }
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

pub(super) enum ReplyInputAction {
    SubmitOriginal,
    Wait,
    FinishUnconsumed,
    ObserveTurn(String),
}

pub(super) enum ReplyTurnAction {
    Wait,
    Preview,
    FinishText,
    AwaitInteraction,
    Close(CardLifecycle),
}

impl ReplyTurnAction {
    pub(super) fn for_snapshot(
        terminal: Option<&TurnState>,
        observed: Option<&TurnState>,
        active: bool,
    ) -> Self {
        match terminal {
            None if matches!(observed, Some(TurnState::Queued(_) | TurnState::Running(_)))
                || observed.is_none() && active =>
            {
                Self::Preview
            }
            Some(TurnState::Completed(state)) => match state.completion() {
                TurnCompletion::Normal => Self::FinishText,
                TurnCompletion::InteractionRequested => Self::AwaitInteraction,
            },
            Some(TurnState::Cancelled(_)) => Self::Close(CardLifecycle::Cancelled),
            Some(TurnState::Failed(_)) => Self::Close(CardLifecycle::Failed),
            Some(TurnState::BudgetLimited(_)) => Self::Close(CardLifecycle::BudgetLimited),
            None | Some(TurnState::Queued(_) | TurnState::Running(_)) => Self::Wait,
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

impl ReplySession {
    pub(super) fn new(runtime: BotRuntime, inbound: &FrozenInbound, worker_id: &str) -> Self {
        Self {
            output: crate::bots::files::feishu_reply_binding(runtime, inbound, worker_id),
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
            delivered_displays: BTreeSet::new(),
            file_delivery_diagnostic: None,
            card: None,
            next_observation: tokio::time::Instant::now(),
        }
    }
}
pub(in crate::bots) fn bot_input_id(bot_id: &str, chat_id: &str, message_id: &str) -> String {
    format!("bot:{bot_id}:{chat_id}:{message_id}")
}

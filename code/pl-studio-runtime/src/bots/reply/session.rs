//! Inbound reply progress and its canonical input and Turn identity.
use crate::bots::{
    InboundWorkOutcome,
    owner::BotRuntime,
    storage::{
        FrozenInbound,
        card::{CardBinding, CardStream},
    },
};
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

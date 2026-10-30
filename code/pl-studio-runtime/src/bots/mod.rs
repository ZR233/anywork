//! 飞书中国版自建应用的原生接入：协议、存储、连接与产品命令。
//!
//! 本模块是机器人配置、连接、入站受理、会话映射与发送的唯一 owner。
//! HTTP、WebSocket、Protobuf 复用成熟组件，产品只维护所需飞书协议。

mod commands;
mod config;
mod connect;
mod credentials;
mod host;
mod inbound;
mod media;
mod occupancy;
mod operation;
mod owner;
mod protocol;
mod registration;
mod reply;
mod send;
mod storage;
mod workspace;

pub(crate) use config::validate_bot_id;
pub(crate) use host::StudioBotSessionHost;
pub(crate) use owner::BotRuntime;
pub(crate) use protocol::error::FeishuError;

/// 一条已受理输入的持久身份读取：显式区分 Ready/Absent，不把读失败折叠成 None。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum BotInputRead {
    /// Already accepted by the resident owner; its durable projection is still catching up.
    NotReady,
    /// 持久索引知道该输入：原始路由与消费状态。
    Ready {
        delivery: pl_core::thread::input::InputDelivery,
        state: pl_core::thread::input::InputState,
    },
    /// 持久索引没有该输入：尚未受理（首个 effect 未提交），不等于未执行过。
    Absent,
}

/// 目标 Turn 的持久 typed 状态读取。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum BotTurnRead {
    Ready(pl_protocol::TurnState),
    /// Turn 条目尚未持久化；不能据此推断 Turn 不存在或已结束。
    Absent,
}

/// 交互类别对自动回复的语义差异。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum BotInteractionKind {
    /// question/Plan 类：决议沿 canonical continuation 输入延续。
    UserInput,
    /// 工具权限：Allowed/Denied 恢复原 Turn，不产生新 continuation。
    Permission,
}

/// 一条交互的 canonical 事实。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct BotInteractionFact {
    pub kind: BotInteractionKind,
    pub status: pl_protocol::InteractionStatus,
    /// Resolved 且存在 canonical continuation 输入时的输入身份。
    pub continuation_input: Option<String>,
}

/// 交互事实读取的三值结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum BotInteractionRead {
    Ready(BotInteractionFact),
    /// 驻留已见终局但持久回执尚未可见：事实未定，不能解释为取消或无 continuation。
    NotReady,
    /// 驻留、checkpoint 与持久回执都不知道该身份。
    Absent,
}

#[derive(Debug, Clone)]
pub(crate) enum SendAuthority {
    Owner,
    AutoReply,
    Tool { workspace_id: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum InboundWorkOutcome {
    Completed,
    /// Runtime 停止观察：原 claim 释放为 pending，立即恢复，不耗失败预算。
    Interrupted,
    /// 真实 retryable 失败：入站账本按分类退避并计数，预算耗尽转需处理。
    Recoverable {
        diagnostic: String,
    },
    NeedsAttention {
        diagnostic: String,
    },
    /// 执行认领已被接管或无法确认续约：本持有者不再收束状态、不再发起新副作用。
    LostClaim,
}

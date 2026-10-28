//! 飞书中国版自建应用的原生接入：协议、存储、连接与产品命令。
//!
//! 本模块是机器人配置、连接、入站受理、会话映射与发送的唯一 owner。
//! HTTP、WebSocket、Protobuf 复用成熟组件，产品只维护所需飞书协议。

mod audience;
mod commands;
mod config;
mod connect;
mod creation;
mod credentials;
mod delivery;
mod host;
mod inbound;
mod ingress;
mod media;
mod occupancy;
mod operation;
mod owner;
mod protocol;
mod publication;
mod registration;
mod send;
mod send_resources;
mod send_service;
mod source;
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
enum SendAuthority {
    Owner,
    InboundReply(Box<storage::reply::InboundReply>),
    Publication(Box<PublicationSendAuthority>),
    Tool { project_id: String },
}

/// 自动前端的发送上下文；只有受信宿主可以组合原作用域、Saved 产物及创建目标。
#[derive(Debug, Clone)]
pub(in crate::bots) struct PublicationSendAuthority {
    pub scope: storage::publication::DeliveryScope,
    pub permit: storage::PublicationFilePermit,
    pub target: storage::target::TargetKind,
}

impl PublicationSendAuthority {
    pub(in crate::bots) fn freeze_bytes(&self, copies: usize) -> Result<usize, FeishuError> {
        let repeated = copies
            .checked_mul(4)
            .ok_or_else(occupancy::freeze_budget_error)?;
        let artifact = &self.permit.artifact;
        let peer = match &self.target {
            storage::target::TargetKind::Group => "",
            storage::target::TargetKind::Direct { open_id } => open_id,
        };
        let bytes = occupancy::counted_text_bytes([
            (self.scope.bot_id.as_str(), repeated),
            (self.scope.chat_id.as_str(), repeated),
            (self.scope.thread_id.as_str(), copies),
            (self.scope.app_id.as_str(), copies),
            (self.scope.project_id.as_str(), copies),
            (self.scope.creation_id.as_str(), copies),
            (self.permit.token.owner_id.as_str(), copies),
            (self.permit.entity.item_id(), copies),
            (self.permit.entity.publication_id(), copies),
            (artifact.thread_id(), copies),
            (artifact.turn_id(), copies),
            (artifact.item_id(), copies),
            (artifact.publication_id(), copies),
            (artifact.tool_call_id(), copies),
            (artifact.display_name(), copies),
            (artifact.resource().id.as_str(), copies),
            (artifact.resource().content_digest.as_str(), copies),
            (artifact.resource().media_type.as_str(), copies),
            (peer, copies),
        ])?;
        occupancy::counted_extra_bytes(bytes, [(1024, copies)])
    }
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
    /// 等待外部就绪（首输入准备）：不计数、不耗失败预算，只按独立等待期限推进重派。
    Deferred {
        diagnostic: String,
    },
    NeedsAttention {
        diagnostic: String,
    },
    /// 原创建身份已证冲突，由入站存储同事务完成工作与 creating 路由收束。
    CreationConflict {
        diagnostic: String,
    },
    /// 执行认领已被接管或无法确认续约：本持有者不再收束状态、不再发起新副作用。
    LostClaim,
}

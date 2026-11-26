//! 飞书中国版自建应用的原生接入：协议、存储、连接与产品命令。
//!
//! 本模块是机器人配置、连接、入站受理、会话映射与发送的唯一 owner。
//! HTTP、WebSocket、Protobuf 复用成熟组件，产品只维护所需飞书协议。

mod archive;
mod binding;
mod config;
mod connect;
mod credentials;
mod files;
mod host;
mod inbound;
mod inbound_dispatch;
mod media;
mod occupancy;
mod operation;
mod owner;
mod protocol;
mod query;
mod registration;
mod registry;
mod reply;
mod send;
mod storage;
#[cfg(test)]
mod test_support;
mod workspace;

pub(crate) use archive::BotArchiveGuard;
pub(crate) use config::load_config;
pub(crate) use config::validate_bot_id;
pub(crate) use host::StudioBotSessionHost;
pub(crate) use owner::BotRuntime;
pub(crate) use protocol::error::FeishuError;

/// Borrow the handle while waiting so cancellation of the waiter leaves it in the owner's slot.
async fn join_owned_task(
    slot: &mut Option<tokio::task::JoinHandle<()>>,
) -> Result<(), tokio::task::JoinError> {
    let Some(handle) = slot.as_mut() else {
        return Ok(());
    };
    let joined = handle.await;
    *slot = None;
    match joined {
        Err(error) if error.is_cancelled() => Ok(()),
        result => result,
    }
}

/// 当前 owner 的有界输入身份；缺失不证明从未受理。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum BotInputRead {
    /// 当前 owner 仍保留该输入的消费状态。
    Ready {
        state: pl_core::thread::input::InputState,
    },
    /// 当前 owner 不再保留该身份，不表示可以重放或重发。
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
    pub status: crate::InteractionStatus,
    /// Resolved 且存在 canonical continuation 输入时的输入身份。
    pub continuation_input: Option<String>,
}

/// 交互事实读取；读取失败独立返回错误。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum BotInteractionRead {
    Ready(BotInteractionFact),
    /// 当前 owner 不保留该交互。
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

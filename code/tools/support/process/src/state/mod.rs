//! Pure process lifecycle observations, shared by exec, stdin and their host.

mod draining;
mod final_state;
mod running;
mod terminating;
use crate::{CommandCaptureOffsets, CommandCaptureStream};
pub use draining::DrainingCommandProcess;
pub use final_state::FinalCommandProcess;
pub use running::RunningCommandProcess;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
pub use terminating::TerminatingCommandProcess;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum CommandProcessLifecycle {
    Running(RunningCommandProcess),
    Terminating(TerminatingCommandProcess),
    Draining(DrainingCommandProcess),
    Final(FinalCommandProcess),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum CommandProcessFinalResult {
    Succeeded { exit_code: i32 },
    Failed { failure: CommandProcessFailure },
    TimedOut,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum CommandProcessFailure {
    Exited {
        exit_code: Option<i32>,
    },
    Wait {
        message: String,
    },
    Output {
        message: String,
        exit_code: Option<i32>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum CommandProcessHealth {
    Healthy,
    OutputFailed { message: String },
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum CommandTerminationReason {
    TimedOut,
    Cancelled,
    /// 该 operation 的捕获不再继续。
    ///
    /// 既可能是命中了声明的单命令落盘上限（预期终止），也可能是捕获写/flush 或读取失败；
    /// 两种情况都会终止进程树、保留已写字节，并按输出事件报告而不是当成用户取消。二者的区别由
    /// [`CommandCaptureFailure`] 的类别携带，调用方不解析诊断文本。
    OutputFailed,
}

impl CommandTerminationReason {
    pub fn message_fragment(self) -> &'static str {
        match self {
            Self::TimedOut => "timed out",
            Self::Cancelled => "was cancelled",
            Self::OutputFailed => "output capture could not continue",
        }
    }
}

/// One accepted capture chunk a failed capture has not stored yet, in acceptance order.
///
/// It keeps the stream the bytes came from, so the repair restores the correct raw file, and the exact
/// accepted bytes, so a retry re-materializes them verbatim instead of re-running the command. The
/// bytes are shared with the reader that accepted them, so retaining the plan never copies output.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CaptureRepairChunk {
    /// Stream whose raw file receives the pending bytes.
    pub stream: CommandCaptureStream,
    /// The accepted chunk the failed capture could not store.
    pub pending: Arc<[u8]>,
}

/// The exact accepted capture bytes a failed capture left off the fragment, with its committed offset.
///
/// A capture write that fails may leave the fragment short of the bytes already accepted and
/// published live, and the *other* stream's reader may already have accepted a following chunk. This
/// names the offset the backend last confirmed — the fragment is truncated back to it — and every
/// accepted chunk the capture did not store, in acceptance order, so one retry re-materializes exactly
/// those bytes, idempotently and without ever re-running the command. The plan is bounded by the
/// operation's shared capture budget, never by the accumulated output.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CaptureRepair {
    /// Length of the capture fragment the backend last confirmed: truncate back here before replaying.
    pub confirmed: CommandCaptureOffsets,
    /// Accepted chunks the failed capture did not store, in the order they were accepted.
    pub chunks: Vec<CaptureRepairChunk>,
}

/// 一条运行中的命令为什么不再继续捕获。
///
/// 类别是 reader 手里已有的值，调用方不需要解析诊断文本就能把它交给自己的存储边界或工具结果，
/// 也正因为类别是值，**预期的容量终止**（[`Self::OutputLimitExceeded`]）与**可靠保存故障**
/// （[`Self::Write`]、[`Self::Read`]）才不会被混为一谈。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CommandCaptureFailure {
    /// 输出触及本 operation 声明的单命令落盘上限：命令被终止，已写字节保留。
    ///
    /// 这是预期内的容量终止，不是落盘故障：它不欠任何可靠保存义务，也不要求显式恢复。
    OutputLimitExceeded {
        /// 本 operation 生效的落盘上限（字节）。
        limit_bytes: u64,
        /// 已被接纳（因此已保留、最终由归档保存）的存储成本。
        charged_bytes: u64,
        /// 被拒绝接纳的存储成本；这些字节从未进入修复计划。
        refused_bytes: u64,
    },
    /// A capture write or flush to disk failed.
    ///
    /// The accepted bytes the failed append could not store are named by the snapshot's
    /// [`CaptureRepair`], so a retry re-materializes exactly those bytes instead of archiving a short
    /// fragment as if it were whole.
    Write {
        message: String,
    },
    Flush {
        message: String,
    },
    /// The operation's own output stream could not be read any further.
    ///
    /// A read failure is not a healthy end of output: the capture is truncated at this point, so the
    /// operation is stopped and reported with the bytes already accepted instead of being treated as a
    /// clean exit. It is typed like a write failure because it is the same "accepted output could not
    /// be captured" fact, and the retained capture can be re-saved through the same obligation.
    Read {
        message: String,
    },
}

impl CommandCaptureFailure {
    /// 出现在命令结果里的可读原因。
    pub fn message(&self) -> String {
        match self {
            Self::OutputLimitExceeded {
                limit_bytes,
                charged_bytes,
                refused_bytes,
            } => format!(
                "command output exceeded the {limit_bytes}-byte per-command capture limit: {charged_bytes} bytes of capture were stored and {refused_bytes} bytes of observed storage cost were refused"
            ),
            Self::Flush { message } => format!("command output capture flush failed: {message}"),
            Self::Write { message } => format!("command output capture failed: {message}"),
            Self::Read { message } => format!("command output stream could not be read: {message}"),
        }
    }
}

impl CommandProcessLifecycle {
    pub fn final_result(&self) -> Option<&CommandProcessFinalResult> {
        match self {
            Self::Final(state) => Some(state.result()),
            Self::Running(_) | Self::Terminating(_) | Self::Draining(_) => None,
        }
    }

    pub fn exit_code(&self) -> Option<i32> {
        match self.final_result() {
            Some(CommandProcessFinalResult::Succeeded { exit_code }) => Some(*exit_code),
            Some(CommandProcessFinalResult::Failed {
                failure:
                    CommandProcessFailure::Exited { exit_code }
                    | CommandProcessFailure::Output { exit_code, .. },
            }) => *exit_code,
            Some(CommandProcessFinalResult::Failed {
                failure: CommandProcessFailure::Wait { .. },
            })
            | Some(CommandProcessFinalResult::TimedOut | CommandProcessFinalResult::Cancelled)
            | None => None,
        }
    }

    pub fn is_timed_out(&self) -> bool {
        matches!(
            self,
            Self::Terminating(state) if state.reason() == CommandTerminationReason::TimedOut
        ) || matches!(
            self,
            Self::Draining(state) if matches!(state.result(), CommandProcessFinalResult::TimedOut)
        ) || matches!(
            self,
            Self::Final(state) if matches!(state.result(), CommandProcessFinalResult::TimedOut)
        )
    }

    pub fn is_final(&self) -> bool {
        matches!(self, Self::Final(_))
    }

    pub fn can_accept_input(&self) -> bool {
        matches!(self, Self::Running(_))
    }
}

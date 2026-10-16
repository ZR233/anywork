//! Command process lifecycle and exact terminal result.

mod draining;
mod final_state;
mod running;
mod terminating;

pub use draining::DrainingCommandProcess;
pub use final_state::FinalCommandProcess;
pub use running::RunningCommandProcess;
pub use terminating::TerminatingCommandProcess;

use serde::{Deserialize, Serialize};
use std::sync::Arc;

use super::{CommandProcessState, HeadTailBuffer, INTERNAL_BUFFER_BYTES, StreamKind};
use crate::command::CommandCaptureStream;

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
pub(super) enum CommandProcessHealth {
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

/// One accepted capture chunk a failed capture has not stored yet, in acceptance order.
///
/// It keeps the stream the bytes came from, so the repair restores the same framing, and the exact
/// accepted bytes, so a retry re-materializes them verbatim instead of re-running the command. The
/// bytes are shared with the reader that accepted them, so retaining the plan never copies output.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CaptureRepairChunk {
    /// Stream the pending bytes came from, so the repair restores the same framing.
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
    pub committed_len: u64,
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
    Write { message: String },
    /// The operation's own output stream could not be read any further.
    ///
    /// A read failure is not a healthy end of output: the capture is truncated at this point, so the
    /// operation is stopped and reported with the bytes already accepted instead of being treated as a
    /// clean exit. It is typed like a write failure because it is the same "accepted output could not
    /// be captured" fact, and the retained capture can be re-saved through the same obligation.
    Read { message: String },
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
                "command output exceeded the {limit_bytes}-byte per-command capture limit: {charged_bytes} bytes of capture were stored and {refused_bytes} bytes of further output were refused"
            ),
            Self::Write { message } => format!("command output capture failed: {message}"),
            Self::Read { message } => format!("command output stream could not be read: {message}"),
        }
    }
}

/// Decision the operation's shared capture plan makes for one read chunk.
///
/// Accepting is the single serialization point for both streams: a chunk joins the bounded plan in
/// the exact order it was read, before it is published, so anything the live observer saw is retained
/// even if the other stream's append fails first. A chunk read after the first fault, or one that
/// would exceed the shared budget, is refused instead of joining the plan.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum CaptureAcceptance {
    /// The chunk joined the bounded plan and is now published and queued for the single writer.
    Accepted,
    /// 本 operation 的落盘上限已满；该 chunk 被拒绝，不进入修复计划。
    ///
    /// 载荷把"上限是多少、已保留多少、被拒多少"一并交回，让终止原因与返回快照都能完整说明
    /// 这次容量终止，而不是只留下"计划满了"这一句。
    OutputLimitExceeded {
        limit_bytes: u64,
        charged_bytes: u64,
        refused_bytes: u64,
    },
    /// A capture fault already stopped admission; the chunk is refused.
    Faulted,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum CommandProcessTransition {
    TimeOut,
    Cancel,
    /// The durable output capture could not continue; terminate the operation but keep its bytes.
    OutputFailed {
        failure: CommandCaptureFailure,
    },
    ProcessExited {
        exit_code: Option<i32>,
    },
    ProcessWaitFailed {
        error: String,
    },
    StreamClosed(StreamKind),
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

    pub(super) fn is_final(&self) -> bool {
        matches!(self, Self::Final(_))
    }

    pub(super) fn can_accept_input(&self) -> bool {
        matches!(self, Self::Running(_))
    }
}

impl CommandProcessState {
    /// Builds the running state with the capture fragment the backend already confirmed.
    ///
    /// `capture_committed_len` is that confirmed length (the prepared header before any chunk), so a
    /// later repair truncates back to a fact the backend reported instead of a length read that could
    /// fail and be mistaken for "nothing written".
    ///
    /// `capture_limit_bytes` 是本 operation 生效的单命令落盘上限，启动时由 backend 声明或取 PL
    /// 默认值；此后不再变化，因此快照与终止原因都引用同一个事实。
    ///
    /// `model_output_bytes_cap` 是同一个 backend 声明的模型可见输出字节上限；`None` 表示沿用
    /// 既有截断语义。两者是不同的边界：前者约束**磁盘**，后者约束进入模型上下文的**正文**。
    pub(super) fn new(
        stdout_open: bool,
        stderr_open: bool,
        capture_committed_len: u64,
        capture_limit_bytes: u64,
        model_output_bytes_cap: Option<u64>,
    ) -> Self {
        Self {
            lifecycle: CommandProcessLifecycle::Running(RunningCommandProcess::healthy()),
            stdout_open,
            stderr_open,
            stdout: HeadTailBuffer::new(INTERNAL_BUFFER_BYTES),
            stderr: HeadTailBuffer::new(INTERNAL_BUFFER_BYTES),
            pending_stdout: HeadTailBuffer::new(INTERNAL_BUFFER_BYTES),
            pending_stderr: HeadTailBuffer::new(INTERNAL_BUFFER_BYTES),
            output_revision: 0,
            capture_limit_bytes,
            capture_charged_bytes: capture_committed_len,
            capture_refused_bytes: 0,
            model_output_bytes_cap,
            capture_committed_len,
            capture_pending: std::collections::VecDeque::new(),
            capture_write_failed: false,
            capture_drained: false,
            output_failure: None,
        }
    }

    pub(super) fn can_accept_input(&self) -> bool {
        self.lifecycle.can_accept_input()
    }

    pub(super) fn record_output(&mut self, stream: StreamKind, chunk: &[u8]) -> u64 {
        self.output_revision = self.output_revision.saturating_add(1);
        match stream {
            StreamKind::Stdout => {
                self.stdout.push_chunk(chunk);
                self.pending_stdout.push_chunk(chunk);
            }
            StreamKind::Stderr => {
                self.stderr.push_chunk(chunk);
                self.pending_stderr.push_chunk(chunk);
            }
        }
        self.output_revision
    }

    /// 把一个已读 chunk 接纳进本 operation 有界、共享、有序的捕获计划。
    ///
    /// 计划是两个流唯一的序列化点：chunk 按读取顺序在**发布之前**入队，因此观察者已经看到的字节
    /// 一定已保留，即使另一个流的 append 先失败。首个故障之后读到的 chunk 一律拒绝。
    ///
    /// `storage_cost` 是 backend 对"把这个 chunk 落盘"的估算（见
    /// [`CommandBackend::capture_storage_cost`](crate::command::CommandBackend::capture_storage_cost)），
    /// 在接纳**之前**计入共享额度：会超出本 operation 上限的 chunk 根本不入队，因此计划与
    /// 磁盘占用被同一个上限约束。这里只拒绝而不写盘，所以容量终止不会被伪装成 IO 失败。
    pub(super) fn accept_capture(
        &mut self,
        stream: CommandCaptureStream,
        chunk: &[u8],
        storage_cost: u64,
    ) -> CaptureAcceptance {
        if self.capture_write_failed || self.output_failure.is_some() {
            self.capture_refused_bytes = self.capture_refused_bytes.saturating_add(storage_cost);
            return CaptureAcceptance::Faulted;
        }
        let next = self.capture_charged_bytes.saturating_add(storage_cost);
        if next > self.capture_limit_bytes {
            self.capture_refused_bytes = self.capture_refused_bytes.saturating_add(storage_cost);
            return CaptureAcceptance::OutputLimitExceeded {
                limit_bytes: self.capture_limit_bytes,
                charged_bytes: self.capture_charged_bytes,
                refused_bytes: self.capture_refused_bytes,
            };
        }
        self.capture_charged_bytes = next;
        self.capture_pending.push_back(CaptureRepairChunk {
            stream,
            pending: Arc::from(chunk),
        });
        CaptureAcceptance::Accepted
    }

    /// 本 operation 生效的单命令落盘上限。
    pub(super) fn capture_limit_bytes(&self) -> u64 {
        self.capture_limit_bytes
    }

    /// 已接纳字节折算出的存储成本累计。
    pub(super) fn capture_charged_bytes(&self) -> u64 {
        self.capture_charged_bytes
    }

    /// 被拒绝接纳的输出折算成本累计。
    pub(super) fn capture_refused_bytes(&self) -> u64 {
        self.capture_refused_bytes
    }

    /// 本 operation 生效的模型可见输出字节上限；`None` 表示沿用既有截断语义。
    pub(super) fn model_output_bytes_cap(&self) -> Option<u64> {
        self.model_output_bytes_cap
    }

    /// The accepted chunk at the front of the plan, without removing it.
    pub(super) fn front_capture(&self) -> Option<CaptureRepairChunk> {
        self.capture_pending.front().cloned()
    }

    /// Confirms the front chunk was stored and the fragment is now `committed_len` bytes long.
    pub(super) fn confirm_front_capture(&mut self, committed_len: u64) {
        self.capture_pending.pop_front();
        self.capture_committed_len = committed_len;
    }

    /// Marks that a capture write failed, so no further chunk may be appended.
    pub(super) fn fault_capture_write(&mut self) {
        self.capture_write_failed = true;
    }

    pub(super) fn capture_write_faulted(&self) -> bool {
        self.capture_write_failed
    }

    /// Whether the plan still holds an accepted chunk the writer has not stored yet.
    pub(super) fn capture_pending_is_empty(&self) -> bool {
        self.capture_pending.is_empty()
    }

    /// Records that the operation's single capture writer has drained the plan and stopped.
    ///
    /// The terminal result is only published once this is set, so no snapshot can report the exit as
    /// final while the writer still owes accepted bytes to disk.
    pub(super) fn mark_capture_drained(&mut self) {
        self.capture_drained = true;
    }

    /// The exact accepted bytes a failed capture must re-materialize, in acceptance order.
    ///
    /// `None` means every accepted chunk the backend confirmed is already on disk, so no repair is
    /// owed. `committed_len` is always the backend's last confirmed length: an append that could not
    /// report a length keeps the previous one, so the plan never falls back to a fragment-length read
    /// that could fail and be mistaken for "nothing to repair".
    pub(super) fn capture_repair(&self) -> Option<CaptureRepair> {
        if self.capture_pending.is_empty() {
            return None;
        }
        Some(CaptureRepair {
            committed_len: self.capture_committed_len,
            chunks: self.capture_pending.iter().cloned().collect(),
        })
    }

    /// Records the reason the durable capture could not continue, before the process is terminated.
    ///
    /// It sets the health so a process that exits on its own still reports the typed output failure,
    /// and it keeps the *first* category/reason: a second reader that reaches the boundary after the
    /// first failure only terminates the same way and must not overwrite what ended the operation. The
    /// accepted chunks neither reader stored stay accumulated in the one capture plan instead of
    /// replacing one another.
    pub(super) fn record_capture_failure(&mut self, failure: CommandCaptureFailure) {
        if self.output_failure.is_none() {
            self.output_failure = Some(failure);
        }
        if let Some(first) = &self.output_failure {
            let message = first.message();
            self.record_output_error(message);
        }
    }

    pub(super) fn record_output_error(&mut self, error: String) {
        match &mut self.lifecycle {
            CommandProcessLifecycle::Running(state) => state.record_output_error(error),
            CommandProcessLifecycle::Draining(state) => state.record_output_error(error),
            CommandProcessLifecycle::Final(state) => state.record_output_error(error),
            CommandProcessLifecycle::Terminating(_) => {}
        }
    }

    pub(super) fn is_final(&self) -> bool {
        self.lifecycle.is_final()
    }

    pub(super) fn apply_transition(&mut self, transition: CommandProcessTransition) {
        match transition {
            CommandProcessTransition::TimeOut
                if matches!(self.lifecycle, CommandProcessLifecycle::Running(_)) =>
            {
                self.lifecycle = CommandProcessLifecycle::Terminating(
                    TerminatingCommandProcess::new(CommandTerminationReason::TimedOut),
                );
            }
            CommandProcessTransition::Cancel
                if matches!(self.lifecycle, CommandProcessLifecycle::Running(_)) =>
            {
                self.lifecycle = CommandProcessLifecycle::Terminating(
                    TerminatingCommandProcess::new(CommandTerminationReason::Cancelled),
                );
            }
            CommandProcessTransition::OutputFailed { failure }
                if matches!(self.lifecycle, CommandProcessLifecycle::Running(_)) =>
            {
                // The first failure already named the reason; a later one only terminates the same
                // way. Keep it so the reported category and reason never regress.
                if self.output_failure.is_none() {
                    self.output_failure = Some(failure);
                }
                self.lifecycle = CommandProcessLifecycle::Terminating(
                    TerminatingCommandProcess::new(CommandTerminationReason::OutputFailed),
                );
            }
            CommandProcessTransition::ProcessExited { exit_code } => {
                let result = match &self.lifecycle {
                    CommandProcessLifecycle::Terminating(state) => match state.reason() {
                        CommandTerminationReason::TimedOut => CommandProcessFinalResult::TimedOut,
                        CommandTerminationReason::Cancelled => CommandProcessFinalResult::Cancelled,
                        CommandTerminationReason::OutputFailed => {
                            CommandProcessFinalResult::Failed {
                                failure: CommandProcessFailure::Output {
                                    message: self.output_failure.as_ref().map_or_else(
                                        || "command output could not be captured".to_string(),
                                        CommandCaptureFailure::message,
                                    ),
                                    exit_code,
                                },
                            }
                        }
                    },
                    CommandProcessLifecycle::Running(state) => match state.health() {
                        CommandProcessHealth::Healthy if exit_code == Some(0) => {
                            CommandProcessFinalResult::Succeeded { exit_code: 0 }
                        }
                        CommandProcessHealth::Healthy => CommandProcessFinalResult::Failed {
                            failure: CommandProcessFailure::Exited { exit_code },
                        },
                        CommandProcessHealth::OutputFailed { message } => {
                            CommandProcessFinalResult::Failed {
                                failure: CommandProcessFailure::Output {
                                    message: message.clone(),
                                    exit_code,
                                },
                            }
                        }
                    },
                    CommandProcessLifecycle::Draining(_) | CommandProcessLifecycle::Final(_) => {
                        return;
                    }
                };
                self.finish_or_drain(result);
            }
            CommandProcessTransition::ProcessWaitFailed { error } => {
                let result = match &self.lifecycle {
                    CommandProcessLifecycle::Terminating(_)
                    | CommandProcessLifecycle::Running(_) => CommandProcessFinalResult::Failed {
                        failure: CommandProcessFailure::Wait { message: error },
                    },
                    CommandProcessLifecycle::Draining(_) | CommandProcessLifecycle::Final(_) => {
                        return;
                    }
                };
                self.finish_or_drain(result);
            }
            CommandProcessTransition::StreamClosed(stream) => {
                match stream {
                    StreamKind::Stdout => self.stdout_open = false,
                    StreamKind::Stderr => self.stderr_open = false,
                }
                // The final result is published here only once the capture writer has settled the
                // plan: a stream closing is not enough on its own, because the writer may still owe
                // the accepted bytes to disk.
                if self.capture_drained
                    && self.output_streams_closed()
                    && let CommandProcessLifecycle::Draining(state) = &self.lifecycle
                {
                    self.lifecycle = CommandProcessLifecycle::Final(FinalCommandProcess::new(
                        state.result().clone(),
                    ));
                }
            }
            CommandProcessTransition::TimeOut
            | CommandProcessTransition::Cancel
            | CommandProcessTransition::OutputFailed { .. } => {}
        }
    }

    fn finish_or_drain(&mut self, result: CommandProcessFinalResult) {
        // Draining keeps the operation non-final until the capture writer has settled, so a snapshot
        // never reports the process exit as final while accepted bytes are still owed to disk.
        self.lifecycle = if self.capture_drained && self.output_streams_closed() {
            CommandProcessLifecycle::Final(FinalCommandProcess::new(result))
        } else {
            CommandProcessLifecycle::Draining(DrainingCommandProcess::new(result))
        };
    }

    /// Promotes a drained, stream-closed operation from `Draining` to `Final`.
    ///
    /// The capture writer calls this after it settles the plan, so an operation whose process already
    /// exited (or whose streams closed after the exit) becomes final without waiting for another
    /// transition that may never come.
    pub(super) fn promote_drained_final(&mut self) {
        if !(self.capture_drained && self.output_streams_closed()) {
            return;
        }
        let result = match &self.lifecycle {
            CommandProcessLifecycle::Draining(state) => state.result().clone(),
            CommandProcessLifecycle::Running(_)
            | CommandProcessLifecycle::Terminating(_)
            | CommandProcessLifecycle::Final(_) => return,
        };
        self.lifecycle = CommandProcessLifecycle::Final(FinalCommandProcess::new(result));
    }

    pub(super) fn output_streams_closed(&self) -> bool {
        !self.stdout_open && !self.stderr_open
    }
}

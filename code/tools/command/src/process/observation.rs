//! Immutable observations from a process owner; no task registry or process handles.
use crate::process::state::*;
use pl_output::TruncatedOutput;
use std::path::PathBuf;

impl From<&CommandOutputSnapshot> for pl_output::OutputTruncation {
    fn from(snapshot: &CommandOutputSnapshot) -> Self {
        Self {
            stdout: snapshot.stdout.clone(),
            stderr: snapshot.stderr.clone(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum StdinCloseState {
    Open,
    Closing,
    Closed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CommandCaptureStream {
    Stdout,
    Stderr,
}

/// 实际捕获写入者交回的终态磁盘计量，拒绝量只包含实际观察到但未接纳的块。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CommandCaptureReceipt {
    pub captured_bytes: u64,
    pub limit_bytes: u64,
    /// 主捕获文件的确认偏移，与包含所有副本的计费成本分开。
    pub confirmed: CommandCaptureOffsets,
    pub charged_bytes: u64,
    pub refused_bytes: u64,
}

/// Each raw stream advances only after its writer confirms the append.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandCaptureOffsets {
    pub stdout: u64,
    pub stderr: u64,
}

impl CommandCaptureOffsets {
    pub fn total(self) -> u64 {
        self.stdout.saturating_add(self.stderr)
    }
    pub fn get(self, stream: CommandCaptureStream) -> u64 {
        match stream {
            CommandCaptureStream::Stdout => self.stdout,
            CommandCaptureStream::Stderr => self.stderr,
        }
    }
    pub fn set(&mut self, stream: CommandCaptureStream, value: u64) {
        match stream {
            CommandCaptureStream::Stdout => self.stdout = value,
            CommandCaptureStream::Stderr => self.stderr = value,
        }
    }
}

#[derive(Debug, Clone, Copy, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub enum CommandInputOutcome {
    Complete,
    Cancelled,
    Partial,
    Failed,
}

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandInputReceipt {
    pub accepted_bytes: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub remote_confirmed_bytes: Option<u64>,
    pub delivery_pending: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub close_state: Option<StdinCloseState>,
    pub outcome: CommandInputOutcome,
    pub detail: Option<String>,
}

#[derive(Debug, Clone)]
pub struct CommandOutputSnapshot {
    pub state: CommandProcessLifecycle,
    pub process_id: Option<String>,
    pub stdout: TruncatedOutput,
    pub stdout_omission_marker: Option<std::ops::Range<usize>>,
    pub stderr_omission_marker: Option<std::ops::Range<usize>>,
    pub stderr: TruncatedOutput,
    pub output_file: PathBuf,
    pub capture_file: PathBuf,
    pub stderr_capture_file: PathBuf,
    pub stderr_output_file: PathBuf,
    pub message: String,
    pub output_revision: u64,
    pub exit_code: Option<i32>,
    pub signal: Option<i32>,
    pub supervision_failure: Option<String>,
    pub input_receipt: Option<CommandInputReceipt>,
    pub stdout_text_lossy: bool,
    pub stderr_text_lossy: bool,
    pub output_artifacts: Vec<serde_json::Value>,
    /// Typed reason the durable capture could not continue, when a hard output failure ended it.
    ///
    /// `None` for a normal exit; a producer maps the category to its own storage boundary without
    /// parsing [`CommandOutputSnapshot::message`].
    pub output_failure: Option<CommandCaptureFailure>,
    /// Accepted capture chunks a failed capture did not store, in acceptance order.
    ///
    /// Derived from the operation's one capture plan when the snapshot is taken, so a retry replays
    /// every accepted chunk (not only the ones the first failing append saw).
    pub capture_plan: Option<CaptureRepair>,
    /// Length of the capture fragment the backend last confirmed writing.
    ///
    /// The accepted bytes this operation really holds are this length plus every chunk still owed, so
    /// a reported size never depends on a fragment-length read that could fail and understate it.
    pub capture_offsets: CommandCaptureOffsets,
    /// 本 operation 实际生效的单命令落盘上限（字节）。
    ///
    /// 它是 backend 声明的值，因此快照能自证"这次上限是多少"，
    /// 调用方不需要回读 backend 配置。
    pub capture_limit_bytes: u64,
    /// 唯一预算执行者确认的存储用量；Producer 回执尚未到达时为 `None`。
    ///
    /// Manager 的 charged 是已接纳的精确写入成本，可能尚在写队列；Producer 的 charged
    /// 来自物理写入者终态回执。`None` 不表示零字节，也不由客户端接收量估算。
    pub capture_usage: Option<CommandCaptureReceipt>,
    /// 本 operation 生效的模型可见输出上限（字节）；`None` 表示沿用既有截断语义。
    ///
    /// 它只约束模型可见正文（stdout/stderr 截断结果之和），不约束工具结果的元数据，
    /// 也不约束磁盘上的捕获与归档；后者由本 operation 的落盘上限负责。
    pub model_output_bytes_cap: Option<u64>,
}

impl CommandOutputSnapshot {
    /// The accepted bytes a failed capture append could not write, when the failure left a repair.
    ///
    /// A write failure that reached the capture file part-way keeps the offset the backend last
    /// confirmed and every accepted chunk it did not store, so a producer re-materializes those bytes
    /// before it archives anything. `None` means every accepted chunk is already on disk, so no repair
    /// is owed.
    pub fn capture_repair(&self) -> Option<&CaptureRepair> {
        self.capture_plan.as_ref()
    }

    /// 本 operation 是否按单命令落盘上限终止；`None` 表示不是容量终止。
    ///
    /// 容量终止是一次**预期内的、自己声明上限**的停止，不是可靠保存故障：已接纳的字节仍在捕获里
    /// 由正常归档路径保存，因此调用方既不该按落盘故障暂停准入，也不该给它挂可靠保存义务。
    pub fn output_limit_exceeded(&self) -> Option<CommandOutputLimit> {
        match self.output_failure.as_ref() {
            Some(CommandCaptureFailure::OutputLimitExceeded {
                limit_bytes,
                charged_bytes,
                refused_bytes,
            }) => Some(CommandOutputLimit {
                limit_bytes: *limit_bytes,
                charged_bytes: *charged_bytes,
                refused_bytes: *refused_bytes,
            }),
            Some(
                CommandCaptureFailure::Write { .. }
                | CommandCaptureFailure::Flush { .. }
                | CommandCaptureFailure::Read { .. },
            )
            | None => None,
        }
    }
}

/// 一次按单命令落盘上限终止的事实：上限、已保留成本与被拒输出成本。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CommandOutputLimit {
    /// 本 operation 生效的落盘上限（字节）。
    pub limit_bytes: u64,
    /// 已接纳（因此已保留、最终由归档保存）的存储成本。
    pub charged_bytes: u64,
    /// 被拒绝接纳的存储成本；这些字节从未进入修复计划。
    pub refused_bytes: u64,
}

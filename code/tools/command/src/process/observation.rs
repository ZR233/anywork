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

/// Per-stream target capture facts. Unknown counts are never replaced with zero.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub enum CommandCaptureState {
    Complete,
    LimitExceeded,
    IoFailed,
    Incomplete,
}
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandCaptureIoError {
    #[serde(serialize_with = "serialize_io_kind")]
    pub kind: std::io::ErrorKind,
    pub raw_os_error: Option<i32>,
}
fn serialize_io_kind<S: serde::Serializer>(
    kind: &std::io::ErrorKind,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    serializer.serialize_str(&format!("{kind:?}"))
}
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandCapturedStream {
    pub state: CommandCaptureState,
    pub confirmed_bytes: Option<u64>,
    pub error: Option<CommandCaptureIoError>,
}
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandCaptureResult {
    pub stdout: CommandCapturedStream,
    pub stderr: CommandCapturedStream,
}
impl CommandCaptureResult {
    pub fn stream(&self, stream: CommandCaptureStream) -> &CommandCapturedStream {
        match stream {
            CommandCaptureStream::Stdout => &self.stdout,
            CommandCaptureStream::Stderr => &self.stderr,
        }
    }
    pub fn confirmed_total(&self) -> Option<u64> {
        self.stdout
            .confirmed_bytes?
            .checked_add(self.stderr.confirmed_bytes?)
    }
    pub fn complete(&self) -> bool {
        self.stdout.state == CommandCaptureState::Complete
            && self.stderr.state == CommandCaptureState::Complete
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
    pub input_receipt: Option<CommandInputReceipt>,
    pub stdout_text_lossy: bool,
    pub stderr_text_lossy: bool,
    pub output_artifacts: Vec<serde_json::Value>,
    /// Typed reason the durable capture could not continue, when a hard output failure ended it.
    ///
    /// `None` for a normal exit; a producer maps the category to its own storage boundary without
    /// parsing [`CommandOutputSnapshot::message`].
    pub output_failure: Option<CommandCaptureFailure>,
    pub capture: Option<CommandCaptureResult>,
    pub capture_limit_bytes: u64,
    /// 本 operation 生效的模型可见输出上限（字节）；`None` 表示沿用既有截断语义。
    ///
    /// 它只约束模型可见正文（stdout/stderr 截断结果之和），不约束工具结果的元数据，
    /// 也不约束磁盘上的捕获与归档；后者由本 operation 的落盘上限负责。
    pub model_output_bytes_cap: Option<u64>,
}

impl CommandOutputSnapshot {
    pub fn confirmed_bytes(&self, stream: CommandCaptureStream) -> Option<u64> {
        self.capture.as_ref()?.stream(stream).confirmed_bytes
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
    pub charged_bytes: Option<u64>,
    /// 被拒绝接纳的存储成本；这些字节从未进入修复计划。
    pub refused_bytes: Option<u64>,
}

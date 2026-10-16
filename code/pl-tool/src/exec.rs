//! Command tool declarations and Thread-owned implementations.
mod progress;
mod thread;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
pub use thread::{CommandAccess, CommandOutputArchive, ExecFailure, ThreadExecTool};
pub const TOOL_EXEC: &str = "exec";
pub const TOOL_WRITE_STDIN: &str = "write_stdin";
const DEFAULT_TIMEOUT_SECS: u64 = 60;
/// `maxOutputChars` 缺省/上限对应的模型可见输出预算，单位是**字节**（见 [`ExecInput`]）。
///
/// 历史上它按"字符"命名，实际计量一直是 `String` 的字节长度；这里只改名不改语义。
const MAX_MODEL_OUTPUT_BYTES: usize = 64 * 1024;
/// `exec` 的结构化输入。
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ExecInput {
    /// The shell command to execute.
    pub command: String,
    /// Optional working directory. Use `.` for the workspace root or a workspace-relative path
    /// such as `src`. SSH execution rejects absolute paths; local absolute paths remain subject to
    /// the active permission and workspace policy.
    #[serde(default)]
    pub cwd: Option<PathBuf>,
    /// Optional total timeout in seconds (default: 60).
    #[serde(default)]
    #[schemars(range(min = 1))]
    pub timeout_seconds: Option<u64>,
    /// Maximum stdout/stderr **bytes** returned to the model.
    ///
    /// The wire field name keeps the historical `maxOutputChars`, but the unit is bytes: the
    /// projection truncates the visible stdout/stderr text by `String` byte length, so multi-byte
    /// characters are charged for their real encoded size. A backend may additionally declare its
    /// own byte ceiling through `CommandBackend::model_output_bytes_cap`.
    #[serde(default)]
    #[schemars(range(min = 1))]
    pub max_output_chars: Option<usize>,
}

/// `write_stdin` 的结构化输入。
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WriteStdinInput {
    /// Task id returned by exec's acceptance receipt.
    pub task_id: String,
    /// Nonempty text to write to stdin. This tool does not wait or poll.
    #[schemars(length(min = 1))]
    pub chars: String,
    /// Maximum stdout/stderr characters returned to the model.
    #[serde(default)]
    #[schemars(range(min = 1))]
    pub max_output_chars: Option<usize>,
}

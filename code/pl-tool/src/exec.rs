//! Command tool declarations and Thread-owned implementations.
mod capture_retention;
mod input;
mod output;
pub use output::permission_denied;
mod progress;
mod thread;
pub use input::{
    ExecInputError, ValidatedExecInput, parse_and_validate_exec_input,
    parse_and_validate_stdin_input,
};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
pub use thread::{CommandAccess, CommandOutputArchive, ExecFailure, ThreadExecTool};
pub const TOOL_EXEC: &str = "exec";
pub const TOOL_WRITE_STDIN: &str = "write_stdin";
const DEFAULT_TIMEOUT_SECS: u64 = 60;
/// `maxOutputChars` 缺省/上限对应的模型可见正文预算，单位是**字节**（见 [`ExecInput`]）。
///
/// 保留历史字段名；按 stdout/stderr 合计的 UTF-8 字节计量，元数据及协议包装另计。
const MAX_MODEL_BODY_BYTES: usize = 64 * 1024;
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
    /// Positive seconds from process-manager admission, including startup (default: 60).
    /// Approval time is excluded; receiving a background receipt does not reset this deadline.
    #[serde(default)]
    // Keep zero expressible so the shared semantic validator can reject the original value
    // before authorization, without a model substituting null/default to satisfy the schema.
    pub timeout_seconds: Option<u64>,
    /// Positive combined stdout + stderr UTF-8 byte budget (default and maximum: 65536).
    /// Metadata, JSON escaping and protocol wrappers are additional and do not consume this budget.
    ///
    /// The wire field name keeps the historical `maxOutputChars`, but the unit is bytes: the
    /// projection truncates the visible stdout/stderr text by `String` byte length, so multi-byte
    /// characters are charged for their real encoded size. A backend may additionally declare its
    /// own byte ceiling through `CommandBackend::model_output_bytes_cap`.
    #[serde(default)]
    pub max_output_chars: Option<usize>,
}

/// `write_stdin` 的结构化输入。
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WriteStdinInput {
    /// Task id returned by exec's acceptance receipt.
    pub task_id: String,
    /// Text to write. Empty is valid only with closeStdin=true; use wait for polling.
    pub chars: String,
    /// Close stdin after the requested text is accepted. Empty text sends only EOF.
    #[serde(default)]
    pub close_stdin: bool,
    /// Positive combined stdout + stderr UTF-8 byte budget, clamped to 65536.
    #[serde(default)]
    pub max_output_chars: Option<usize>,
}
